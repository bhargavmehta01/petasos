import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cards/card_widgets.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../screens/settings_screen.dart' show showCronEditor;
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'wave3_api.dart';
import 'wave3_models.dart';
import '../wave2_parity/w2_settings.dart';

/// Health of a job from its list row and (when loaded) its newest run.
CronHealth cronHealth(HermesMobileCronJob job, [CronJobDetail? detail]) {
  if (job.paused) return CronHealth.paused;
  final latest = detail?.runs.isNotEmpty == true ? detail!.runs.first : null;
  if (latest?.ok == false) return CronHealth.failing;
  final s = (job.lastStatus ?? '').toLowerCase();
  if (RegExp(r'err|fail|timeout|crash').hasMatch(s)) return CronHealth.failing;
  if (latest?.ok == true || s == 'ok' || s == 'success' || s == 'done') {
    return CronHealth.healthy;
  }
  return CronHealth.unknown;
}

String cronHealthLabel(CronHealth h) => switch (h) {
  CronHealth.healthy => 'Healthy',
  CronHealth.failing => 'Failing',
  CronHealth.paused => 'Paused',
  CronHealth.unknown => 'No runs yet',
};

class CronHealthDot extends StatelessWidget {
  const CronHealthDot(this.health, {super.key, this.size = 10});
  final CronHealth health;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final color = switch (health) {
      CronHealth.healthy => c.success,
      CronHealth.failing => c.danger,
      CronHealth.paused => c.textTertiary,
      CronHealth.unknown => c.warning,
    };
    return Semantics(
      label: cronHealthLabel(health),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

String _ago(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Cron studio: every scheduled task with a health dot and a strip of its
/// recent runs. Tap a task for its timeline, last output and failure reason.
class CronStudioScreen extends StatefulWidget {
  const CronStudioScreen({super.key});
  @override
  State<CronStudioScreen> createState() => _CronStudioScreenState();
}

class _CronStudioScreenState extends State<CronStudioScreen> {
  Future<List<HermesMobileCronJob>>? _jobs;
  final Map<String, Future<CronJobDetail>> _details = {};

  void _reload() {
    final state = HermesMobileScope.read(context);
    setState(() {
      _details.clear();
      _jobs = state.backend.listCron();
    });
  }

  Future<CronJobDetail> _detail(HermesMobileCronJob j) => _details.putIfAbsent(
    j.id,
    () => Wave3Api.of(HermesMobileScope.read(context).backend).cronDetail(j),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _jobs ??= HermesMobileScope.read(context).backend.listCron();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cron studio')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await showCronEditor(context);
          if (ok == true) _reload();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _jobs;
        },
        child: FutureBuilder<List<HermesMobileCronJob>>(
          future: _jobs,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList(count: 4);
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load scheduled tasks',
                    body:
                        'Scheduled tasks come from the Hermes dashboard. '
                        'Check its URL under Connection.\n${snap.error}',
                    action: TextButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }
            final jobs = snap.data ?? const [];
            if (jobs.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(
                    icon: Icons.schedule_rounded,
                    title: 'No scheduled tasks',
                    body: 'Create one, or ask Hermes to schedule something.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final j = jobs[i];
                return FutureBuilder<CronJobDetail>(
                  future: _detail(j),
                  builder: (context, d) => _JobCard(
                    job: j,
                    detail: d.data,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HermesMobileScope(
                            state: HermesMobileScope.read(context),
                            child: CronJobScreen(job: j),
                          ),
                        ),
                      );
                      if (mounted) _reload();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, this.detail, this.onTap});
  final HermesMobileCronJob job;
  final CronJobDetail? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final health = cronHealth(job, detail);
    return HermesMobileCardFrame(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CronHealthDot(health),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  job.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(cronHealthLabel(health), style: t.labelSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            job.schedule,
            style: t.bodySmall?.copyWith(
              color: c.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (detail != null && detail!.runs.isNotEmpty) ...[
            const SizedBox(height: 10),
            RunStrip(runs: detail!.runs),
          ],
          if (health == CronHealth.failing &&
              (detail?.lastError ?? detail?.runs.first.error) != null) ...[
            const SizedBox(height: 8),
            Text(
              detail!.lastError ?? detail!.runs.first.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: c.danger),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            [
              if (!job.paused && job.nextRun != null) 'Next: ${job.nextRun}',
              if (detail?.runs.isNotEmpty == true)
                'Last: ${_ago(detail!.runs.first.startedAt)}',
            ].join(' · '),
            style: t.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// Newest-last strip of run outcomes: green ok, red failed, grey unknown.
class RunStrip extends StatelessWidget {
  const RunStrip({super.key, required this.runs, this.max = 14});
  final List<CronRunRecord> runs;
  final int max;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final shown = runs.take(max).toList().reversed.toList();
    return Row(
      children: [
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message:
                  '${r.ok == false
                      ? 'Failed'
                      : r.ok == true
                      ? 'OK'
                      : 'Unknown'} · ${_ago(r.startedAt)}',
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: r.ok == false
                      ? c.danger
                      : r.ok == true
                      ? c.success.withValues(alpha: 0.8)
                      : c.surfaceMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One task: health, failure reason, last output, run timeline and actions.
class CronJobScreen extends StatefulWidget {
  const CronJobScreen({super.key, required this.job});
  final HermesMobileCronJob job;
  @override
  State<CronJobScreen> createState() => _CronJobScreenState();
}

class _CronJobScreenState extends State<CronJobScreen> {
  late HermesMobileCronJob _job = widget.job;
  Future<CronJobDetail>? _detail;
  final Map<String, Future<String?>> _outputs = {};
  String? _openRun;

  Wave3Api get _api => Wave3Api.of(HermesMobileScope.read(context).backend);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= _api.cronDetail(_job);
  }

  void _reload() => setState(() {
    _outputs.clear();
    _detail = _api.cronDetail(_job);
  });

  Future<void> _act(Future<void> Function() f, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await f();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final b = HermesMobileScope.of(context).backend;
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_job.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final ok = await showCronEditor(context, job: _job);
              if (ok == true && context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<CronJobDetail>(
          future: _detail,
          builder: (context, snap) {
            final d = snap.data;
            final health = cronHealth(_job, d);
            final failure =
                d?.lastError ??
                (d?.runs.isNotEmpty == true ? d!.runs.first.error : null);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                HermesMobileCardFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CronHealthDot(health, size: 12),
                          const SizedBox(width: 8),
                          Text(
                            cronHealthLabel(health),
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: !_job.paused,
                            onChanged: (on) => _act(() async {
                              W2Haptics.selection();
                              await b.setCronPaused(_job.id, !on);
                              setState(() => _job = _copyPaused(_job, !on));
                            }, on ? 'Resumed' : 'Paused'),
                          ),
                        ],
                      ),
                      Text(
                        _job.schedule,
                        style: t.bodySmall?.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_job.nextRun != null && !_job.paused)
                        Text('Next run: ${_job.nextRun}', style: t.labelSmall),
                      const SizedBox(height: 8),
                      Text(_job.prompt, style: t.bodySmall),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _act(() => b.runCron(_job.id), 'Started a run');
                            },
                            icon: const Icon(Icons.replay_rounded, size: 18),
                            label: const Text('Run now'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _reload,
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (failure != null && health == CronHealth.failing) ...[
                  const SectionHeader('Why it failed'),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(HermesMobileRadius.card),
                      border: Border.all(
                        color: c.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SelectableText(
                      failure,
                      style: t.bodyMedium?.copyWith(color: c.danger),
                    ),
                  ),
                ],
                if (d?.lastOutput != null &&
                    d!.lastOutput!.trim().isNotEmpty) ...[
                  const SectionHeader('Last output'),
                  HermesMobileCardFrame(child: SelectableText(d.lastOutput!)),
                ],
                if (d != null) ...[
                  SectionHeader(
                    'Run history',
                    trailing: Text(
                      '${d.runs.length} run${d.runs.length == 1 ? '' : 's'}',
                      style: t.labelSmall,
                    ),
                  ),
                  if (d.runs.isEmpty)
                    const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No runs yet',
                      body: 'Runs appear here after the task fires.',
                    )
                  else
                    HermesMobileCardFrame(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < d.runs.length; i++)
                            _TimelineRow(
                              run: d.runs[i],
                              first: i == 0,
                              last: i == d.runs.length - 1,
                              open: _openRun == d.runs[i].id,
                              output: _outputs[d.runs[i].id],
                              onTap: () => setState(() {
                                final id = d.runs[i].id;
                                _openRun = _openRun == id ? null : id;
                                if (_openRun != null) {
                                  _outputs.putIfAbsent(
                                    id,
                                    () => _api
                                        .runOutput(id)
                                        .catchError(
                                          (Object e) =>
                                              'Could not load output: $e',
                                        ),
                                  );
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static HermesMobileCronJob _copyPaused(HermesMobileCronJob j, bool paused) => HermesMobileCronJob(
    id: j.id,
    name: j.name,
    schedule: j.schedule,
    prompt: j.prompt,
    paused: paused,
    nextRun: j.nextRun,
    lastRun: j.lastRun,
    lastStatus: j.lastStatus,
    deliver: j.deliver,
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.run,
    required this.first,
    required this.last,
    required this.open,
    required this.onTap,
    this.output,
  });
  final CronRunRecord run;
  final bool first;
  final bool last;
  final bool open;
  final VoidCallback onTap;
  final Future<String?>? output;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final color = run.ok == false
        ? c.danger
        : run.ok == true
        ? c.success
        : c.textTertiary;
    final dur = run.duration;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 18,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: 2,
                        color: first ? Colors.transparent : c.hairline,
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        color: last ? Colors.transparent : c.hairline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_fmt(run.startedAt)} · ${_ago(run.startedAt)}',
                              style: t.bodyMedium,
                            ),
                          ),
                          if (dur != null)
                            Text('${dur.inSeconds}s', style: t.labelSmall),
                          Icon(
                            open
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: c.textTertiary,
                          ),
                        ],
                      ),
                      if (run.error != null)
                        Text(
                          run.error!,
                          maxLines: open ? null : 1,
                          overflow: open ? null : TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: c.danger),
                        )
                      else if (run.preview.isNotEmpty && !open)
                        Text(
                          run.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                      if (open && output != null)
                        FutureBuilder<String?>(
                          future: output,
                          builder: (context, s) {
                            if (s.connectionState != ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.all(8),
                                child: LinearProgressIndicator(minHeight: 2),
                              );
                            }
                            final text = s.data;
                            return Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: c.surfaceMuted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: SelectableText(
                                text == null || text.isEmpty
                                    ? 'No output for this run.'
                                    : text,
                                style: t.bodySmall,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${two(t.hour)}:${two(t.minute)}';
  }
}
