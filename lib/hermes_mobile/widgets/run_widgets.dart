import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../theme/hermes_mobile_theme.dart';

/// Friendly, present-tense label for a tool name.
String friendlyToolLabel(String raw) {
  final n = raw.toLowerCase().replaceAll(' ', '_');
  if (n.contains('search')) return 'Searching the web';
  if (n.contains('extract') || n.contains('fetch') || n.contains('crawl')) {
    return 'Reading a page';
  }
  if (n.startsWith('browser')) return 'Using the browser';
  if (n.contains('terminal') || n.contains('shell') || n.contains('exec')) {
    return 'Running a command';
  }
  if (n.contains('read_file') || n.contains('search_files')) {
    return 'Reading files';
  }
  if (n.contains('write_file') || n.contains('patch') || n.contains('edit')) {
    return 'Editing a file';
  }
  if (n.contains('memory')) return 'Checking memory';
  if (n.contains('delegate') || n.contains('subagent')) {
    return 'Delegating a task';
  }
  if (n.contains('image')) return 'Working with images';
  if (n.contains('calendar')) return 'Checking the calendar';
  if (n.contains('mail')) return 'Checking email';
  if (n.contains('cron')) return 'Scheduling';
  if (n.contains('skill')) return 'Using a skill';
  final words = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return words.isEmpty ? 'Working' : words[0].toUpperCase() + words.substring(1);
}

/// One compact live card per run: title, current step, expandable steps,
/// Stop. Never a wall of tool logs.
class TaskCard extends StatefulWidget {
  const TaskCard({super.key, required this.run, this.onStop});
  final HermesMobileRun run;
  final VoidCallback? onStop;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final run = widget.run;
    final runningNow = run.status == HermesMobileRunStatus.running;
    final done = run.steps.where((s) => s.state == HermesMobileStepState.done).length;
    final failed = run.status == HermesMobileRunStatus.failed;
    final headline = runningNow
        ? run.currentLine
        : switch (run.status) {
            HermesMobileRunStatus.done =>
              run.steps.isEmpty
                  ? 'Done'
                  : 'Done · ${run.steps.length} step${run.steps.length == 1 ? '' : 's'}',
            HermesMobileRunStatus.failed => 'Stopped by an error',
            HermesMobileRunStatus.stopped => 'Stopped',
            HermesMobileRunStatus.running => '',
          };
    final stepLabel = runningNow && run.steps.isNotEmpty
        ? _stepText(run.steps.lastWhere(
            (s) => s.state == HermesMobileStepState.running,
            orElse: () => run.steps.last,
          ))
        : headline;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(HermesMobileRadius.card),
          border: Border.all(color: c.hairline),
          boxShadow: hermesMobileShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(HermesMobileRadius.card),
              onTap: run.steps.isEmpty && run.reasoning.isEmpty
                  ? null
                  : () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: runningNow
                          ? Padding(
                              padding: const EdgeInsets.all(3),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.accent,
                              ),
                            )
                          : Icon(
                              failed
                                  ? Icons.error_outline_rounded
                                  : run.status == HermesMobileRunStatus.stopped
                                  ? Icons.stop_circle_outlined
                                  : Icons.check_circle_rounded,
                              size: 20,
                              color: failed
                                  ? c.danger
                                  : run.status == HermesMobileRunStatus.stopped
                                  ? c.textTertiary
                                  : c.success,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            runningNow ? run.title : headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (runningNow) ...[
                            const SizedBox(height: 2),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                stepLabel,
                                key: ValueKey(stepLabel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (run.steps.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          runningNow ? '$done/${run.steps.length}' : '',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    if (runningNow && widget.onStop != null)
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.onStop!();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: c.danger,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Stop'),
                      )
                    else if (run.steps.isNotEmpty || run.reasoning.isNotEmpty)
                      Icon(
                        _open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: c.textTertiary,
                      ),
                  ],
                ),
              ),
            ),
            if (_open) ...[
              Divider(height: 1, color: c.hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in run.steps) _StepRow(step: s),
                    if (run.reasoning.trim().isNotEmpty)
                      ThinkingDisclosure(text: run.reasoning),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stepText(HermesMobileStep s) {
    final label = friendlyToolLabel(s.label);
    final d = s.detail?.trim();
    return d == null || d.isEmpty ? label : '$label · $d';
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});
  final HermesMobileStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final icon = switch (step.state) {
      HermesMobileStepState.running => SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: c.accent),
      ),
      HermesMobileStepState.done => Icon(Icons.check_rounded, size: 14, color: c.success),
      HermesMobileStepState.failed => Icon(Icons.close_rounded, size: 14, color: c.danger),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: SizedBox(width: 16, child: Center(child: icon)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: friendlyToolLabel(step.label),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (step.detail?.trim().isNotEmpty == true)
                    TextSpan(
                      text: '  ${step.detail}',
                      style: TextStyle(color: c.textSecondary),
                    ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: c.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small "Thinking" disclosure; reasoning stays hidden until tapped.
class ThinkingDisclosure extends StatefulWidget {
  const ThinkingDisclosure({super.key, required this.text});
  final String text;
  @override
  State<ThinkingDisclosure> createState() => _ThinkingDisclosureState();
}

class _ThinkingDisclosureState extends State<ThinkingDisclosure> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_alt_outlined, size: 15, color: c.textTertiary),
                const SizedBox(width: 6),
                Text(
                  'Thinking',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.textTertiary,
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 16,
                  color: c.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.text.trim(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

/// Inline approval: what and why, then Deny / Allow once / Always.
class ApprovalCard extends StatefulWidget {
  const ApprovalCard({super.key, required this.approval, required this.onAnswer});
  final HermesMobileApproval approval;
  final Future<void> Function(String choice) onAnswer;

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  String? _busy;

  Future<void> _answer(String choice) async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = choice);
    await widget.onAnswer(choice);
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final a = widget.approval;
    final hasAlways = a.choices.contains('always');
    final hasSession = a.choices.contains('session');
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(HermesMobileRadius.card),
        border: Border.all(color: c.warning.withValues(alpha: 0.5)),
        boxShadow: hermesMobileShadow(context),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: c.warning),
              const SizedBox(width: 8),
              Text(
                'Hermes needs your OK',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(a.description, style: Theme.of(context).textTheme.bodyMedium),
          if (a.command.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.codeBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                a.command,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: c.text,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy != null ? null : () => _answer('deny'),
                  style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                  child: const Text('Deny'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _busy != null ? null : () => _answer('once'),
                  child: _busy == 'once'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Allow once'),
                ),
              ),
            ],
          ),
          if (hasAlways || hasSession)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasSession)
                  TextButton(
                    onPressed: _busy != null ? null : () => _answer('session'),
                    child: const Text('This session'),
                  ),
                if (hasAlways)
                  TextButton(
                    onPressed: _busy != null ? null : () => _answer('always'),
                    child: const Text('Always'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Three soft dots while the agent works and no text has arrived.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});
  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hermesMobile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: h.agentBubble,
        borderRadius: BorderRadius.circular(HermesMobileRadius.bubble),
        border: Border.all(color: h.hairline),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity:
                      (0.3 + 0.7 * (1 - ((_c.value * 3 - i) % 3).clamp(0.0, 1.0)))
                          .toDouble(),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: h.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
