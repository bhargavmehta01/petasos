import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cards/card_widgets.dart';
import '../../chat/chat_controller.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/run_widgets.dart';
import 'run_insights.dart';

/// Opens the live run view for [controller].
Future<void> openLiveRun(BuildContext context, ChatController controller) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HermesMobileScope(
          state: HermesMobileScope.read(context),
          child: LiveRunScreen(controller: controller),
        ),
      ),
    );

/// A small bar above the composer while a run is going: tap for the run view.
class LiveRunBar extends StatelessWidget {
  const LiveRunBar({super.key, required this.controller});
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final run = controller.liveRun;
    if (run == null) return const SizedBox.shrink();
    final c = context.hermesMobile;
    final changed = RunInsights.from(run);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Material(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(HermesMobileRadius.chip),
        child: InkWell(
          key: const Key('w3-live-run-bar'),
          borderRadius: BorderRadius.circular(HermesMobileRadius.chip),
          onTap: () => openLiveRun(context, controller),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.monitor_heart_outlined, size: 18, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      'Live run · ${run.steps.length} step${run.steps.length == 1 ? '' : 's'}',
                      if (changed.commands.isNotEmpty)
                        '${changed.commands.length} cmd',
                      if (changed.filesChanged.isNotEmpty)
                        '${changed.filesChanged.length} file${changed.filesChanged.length == 1 ? '' : 's'}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: c.accent),
                  ),
                ),
                Text(
                  'Pause · Steer · Take over',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Icon(Icons.chevron_right_rounded, color: c.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen view of one agent run: steps with timing, files touched,
/// commands, reasoning, and controls to pause, steer, take over or stop.
class LiveRunScreen extends StatefulWidget {
  const LiveRunScreen({
    super.key,
    required this.controller,
    this.support = RunControlSupport.hermesApiServer,
  });
  final ChatController controller;
  final RunControlSupport support;

  @override
  State<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends State<LiveRunScreen> {
  ChatController get ctl => widget.controller;
  final Map<String, DateTime> _firstSeen = {};
  final Map<String, DateTime> _settledAt = {};
  Timer? _tick;
  bool _paused = false;
  bool _busy = false;
  HermesMobileRun? _shown;

  @override
  void initState() {
    super.initState();
    ctl.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ctl.running) setState(() {});
    });
    _onChange();
  }

  @override
  void dispose() {
    ctl.removeListener(_onChange);
    _tick?.cancel();
    super.dispose();
  }

  /// The run to show: the live one, else the newest finished one.
  HermesMobileRun? get _run {
    if (ctl.liveRun != null) return ctl.liveRun;
    for (final m in ctl.messages.reversed) {
      final r = ctl.runs[m];
      if (r != null) return r;
    }
    return null;
  }

  void _onChange() {
    final run = _run;
    if (run == null) return;
    if (!identical(run, _shown)) {
      _shown = run;
      if (run.status == HermesMobileRunStatus.running) _paused = false;
    }
    final now = DateTime.now();
    for (final s in run.steps) {
      _firstSeen.putIfAbsent(s.id, () => now);
      if (s.state != HermesMobileStepState.running) {
        _settledAt.putIfAbsent(s.id, () => now);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() => _guard(() async {
    HapticFeedback.lightImpact();
    await ctl.stop();
    setState(() => _paused = true);
  });

  Future<void> _resume() => _guard(() async {
    setState(() => _paused = false);
    unawaited(ctl.send(resumePrompt));
  });

  Future<void> _steer() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SteerSheet(),
    );
    if (text == null || text.trim().isEmpty) return;
    await _guard(() async {
      if (ctl.running) await ctl.stop();
      setState(() => _paused = false);
      unawaited(ctl.send(steerPrompt(text)));
    });
  }

  Future<void> _takeOver() async {
    final run = _run;
    if (run == null) return;
    if (ctl.running) {
      await _guard(() => ctl.stop());
      if (mounted) setState(() => _paused = true);
    }
    if (!mounted) return;
    final dashboard = HermesMobileScope.read(context).backend.connection.dashboard;
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TakeOverSheet(
        insights: RunInsights.from(run),
        dashboardUrl: dashboard,
      ),
    );
    if (note != null && mounted) {
      setState(() => _paused = false);
      unawaited(ctl.send(handBackPrompt(note)));
    }
  }

  String _elapsed(HermesMobileRun run) {
    final d = DateTime.now().difference(run.startedAt);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final run = _run;
    if (run == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Run')),
        body: const EmptyState(
          icon: Icons.monitor_heart_outlined,
          title: 'Nothing running',
          body: 'Send a message and its run shows up here.',
        ),
      );
    }
    final running = run.status == HermesMobileRunStatus.running;
    final insights = RunInsights.from(run);
    final statusText = _paused
        ? 'Paused'
        : switch (run.status) {
            HermesMobileRunStatus.running => run.currentLine,
            HermesMobileRunStatus.done => 'Done',
            HermesMobileRunStatus.failed => 'Stopped by an error',
            HermesMobileRunStatus.stopped => 'Stopped',
          };
    return Scaffold(
      appBar: AppBar(title: const Text('Live run')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            HermesMobileCardFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (running)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accent,
                          ),
                        )
                      else
                        Icon(
                          _paused
                              ? Icons.pause_circle_outline_rounded
                              : run.status == HermesMobileRunStatus.done
                              ? Icons.check_circle_rounded
                              : Icons.stop_circle_outlined,
                          color: _paused
                              ? c.warning
                              : run.status == HermesMobileRunStatus.done
                              ? c.success
                              : c.textTertiary,
                          size: 20,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          run.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(_elapsed(run), style: t.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusText,
                    key: const Key('w3-run-status'),
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Stat('${run.steps.length}', 'steps'),
                      _Stat('${insights.commands.length}', 'commands'),
                      _Stat('${insights.filesChanged.length}', 'files changed'),
                      _Stat('${insights.filesRead.length}', 'files read'),
                    ],
                  ),
                ],
              ),
            ),
            if (ctl.approval != null) ...[
              const SizedBox(height: 10),
              ApprovalCard(approval: ctl.approval!, onAnswer: ctl.answer),
            ],
            const SizedBox(height: 10),
            _Controls(
              running: running,
              paused: _paused,
              busy: _busy,
              onPause: _pause,
              onResume: _resume,
              onSteer: _steer,
              onTakeOver: _takeOver,
              onStop: () => _guard(() async {
                await ctl.stop();
                setState(() => _paused = false);
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                RunControlSupport.explain(widget.support.steer),
                style: t.labelSmall,
              ),
            ),
            SectionHeader('Steps'),
            if (run.steps.isEmpty)
              HermesMobileCardFrame(
                child: Text(
                  running ? 'Thinking…' : 'No tool steps in this run.',
                  style: t.bodySmall,
                ),
              )
            else
              HermesMobileCardFrame(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final s in run.steps)
                      _StepLine(
                        step: s,
                        startedAt: _firstSeen[s.id],
                        settledAt: _settledAt[s.id],
                        runStart: run.startedAt,
                      ),
                  ],
                ),
              ),
            if (insights.filesChanged.isNotEmpty) ...[
              const SectionHeader('Files changed'),
              _ListCard(
                items: insights.filesChanged,
                icon: Icons.edit_note_rounded,
              ),
            ],
            if (insights.filesRead.isNotEmpty) ...[
              const SectionHeader('Files read'),
              _ListCard(
                items: insights.filesRead,
                icon: Icons.description_outlined,
              ),
            ],
            if (insights.commands.isNotEmpty) ...[
              const SectionHeader('Commands'),
              _ListCard(
                items: insights.commands,
                icon: Icons.terminal_rounded,
                mono: true,
              ),
            ],
            if (insights.web.isNotEmpty) ...[
              const SectionHeader('Web'),
              _ListCard(items: insights.web, icon: Icons.public_rounded),
            ],
            if (run.reasoning.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              ThinkingDisclosure(text: run.reasoning),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(HermesMobileRadius.chip),
      ),
      child: Text(
        '$value $label',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.running,
    required this.paused,
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onSteer,
    required this.onTakeOver,
    required this.onStop,
  });
  final bool running;
  final bool paused;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSteer;
  final VoidCallback onTakeOver;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (paused)
          FilledButton.icon(
            key: const Key('w3-resume'),
            onPressed: busy ? null : onResume,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Resume'),
          )
        else
          FilledButton.tonalIcon(
            key: const Key('w3-pause'),
            onPressed: busy || !running ? null : onPause,
            icon: const Icon(Icons.pause_rounded, size: 18),
            label: const Text('Pause'),
          ),
        FilledButton.tonalIcon(
          key: const Key('w3-steer'),
          onPressed: busy ? null : onSteer,
          icon: const Icon(Icons.alt_route_rounded, size: 18),
          label: const Text('Steer'),
        ),
        FilledButton.tonalIcon(
          key: const Key('w3-takeover'),
          onPressed: busy ? null : onTakeOver,
          icon: const Icon(Icons.pan_tool_alt_outlined, size: 18),
          label: const Text('Take over'),
        ),
        if (running)
          TextButton.icon(
            key: const Key('w3-stop'),
            onPressed: busy ? null : onStop,
            style: TextButton.styleFrom(foregroundColor: c.danger),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Stop'),
          ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({
    required this.step,
    required this.runStart,
    this.startedAt,
    this.settledAt,
  });
  final HermesMobileStep step;
  final DateTime runStart;
  final DateTime? startedAt;
  final DateTime? settledAt;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final at = startedAt;
    final offset = at?.difference(runStart).inSeconds;
    final took = at == null
        ? null
        : (settledAt ?? DateTime.now()).difference(at).inSeconds;
    return ListTile(
      dense: true,
      leading: switch (step.state) {
        HermesMobileStepState.running => SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
        ),
        HermesMobileStepState.done => Icon(
          Icons.check_rounded,
          size: 18,
          color: c.success,
        ),
        HermesMobileStepState.failed => Icon(
          Icons.close_rounded,
          size: 18,
          color: c.danger,
        ),
      },
      title: Text(
        friendlyToolLabel(step.label),
        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: step.detail == null || step.detail!.isEmpty
          ? null
          : Text(
              step.detail!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall,
            ),
      trailing: offset == null
          ? null
          : Text(
              '+${offset}s${took != null && took > 0 ? ' · ${took}s' : ''}',
              style: t.labelSmall,
            ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.items, required this.icon, this.mono = false});
  final List<String> items;
  final IconData icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    return HermesMobileCardFrame(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final i in items)
            ListTile(
              dense: true,
              leading: Icon(icon, size: 18, color: c.textSecondary),
              title: Text(
                i,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: mono
                    ? t.bodySmall?.copyWith(fontFamily: 'monospace')
                    : t.bodySmall,
              ),
              trailing: IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: i));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SteerSheet extends StatefulWidget {
  const _SteerSheet();
  @override
  State<_SteerSheet> createState() => _SteerSheetState();
}

class _SteerSheetState extends State<_SteerSheet> {
  final _text = TextEditingController();
  static const _quick = [
    'Keep it shorter',
    'Use a different approach',
    'Skip that step',
    'Ask me before changing files',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Steer this run',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Hermes stops, then carries on with your change. Finished steps are kept.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in _quick)
                ActionChip(label: Text(q), onPressed: () => _text.text = q),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('w3-steer-field'),
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'What should change?'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('w3-steer-send'),
            onPressed: () => Navigator.of(context).pop(_text.text),
            child: const Text('Steer'),
          ),
        ],
      ),
    );
  }
}

class _TakeOverSheet extends StatefulWidget {
  const _TakeOverSheet({required this.insights, this.dashboardUrl});
  final RunInsights insights;
  final String? dashboardUrl;
  @override
  State<_TakeOverSheet> createState() => _TakeOverSheetState();
}

class _TakeOverSheetState extends State<_TakeOverSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final i = widget.insights;
    final all = [...i.commands];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Text('You have the wheel', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Hermes has stopped. Here is what it ran and touched so you can '
            'carry on by hand. When you are done, hand it back with a note.',
            style: t.bodySmall,
          ),
          if (all.isNotEmpty) ...[
            const SectionHeader('Commands so far'),
            _ListCard(items: all, icon: Icons.terminal_rounded, mono: true),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: all.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied all commands')),
                  );
                },
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Copy all'),
              ),
            ),
          ],
          if (i.filesChanged.isNotEmpty) ...[
            const SectionHeader('Files it changed'),
            _ListCard(items: i.filesChanged, icon: Icons.edit_note_rounded),
          ],
          if (i.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No commands or file changes yet.',
                style: t.bodySmall,
              ),
            ),
          if (widget.dashboardUrl != null && widget.dashboardUrl!.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(widget.dashboardUrl!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open the Hermes dashboard'),
            ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('w3-handback-note'),
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'What did you do? (optional)',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep it stopped'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('w3-handback'),
                onPressed: () => Navigator.of(context).pop(_note.text),
                child: const Text('Hand back to Hermes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
