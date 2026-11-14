import 'package:flutter/material.dart';

import '../../cards/card_widgets.dart';
import '../../data/app_state.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/undo.dart';
import 'wave3_api.dart';
import 'wave3_models.dart';
import '../wave2_parity/w2_settings.dart';

String expiryLabel(ApprovalRule r, [DateTime? now]) {
  final e = r.expiresAt;
  if (e == null) return 'Never expires';
  final d = e.difference(now ?? DateTime.now());
  if (d.isNegative) return 'Expired';
  if (d.inHours < 1) return 'Expires in ${d.inMinutes.clamp(1, 59)}m';
  if (d.inDays < 1) return 'Expires in ${d.inHours}h';
  return 'Expires in ${d.inDays}d';
}

String riskLabel(RuleRisk r) => switch (r) {
  RuleRisk.high => 'High risk',
  RuleRisk.medium => 'Medium risk',
  RuleRisk.low => 'Low risk',
};

Color riskColor(BuildContext context, RuleRisk r) {
  final c = context.hermesMobile;
  return switch (r) {
    RuleRisk.high => c.danger,
    RuleRisk.medium => c.warning,
    RuleRisk.low => c.success,
  };
}

class RiskChip extends StatelessWidget {
  const RiskChip(this.risk, {super.key});
  final RuleRisk risk;
  @override
  Widget build(BuildContext context) {
    final color = riskColor(context, risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HermesMobileRadius.chip),
      ),
      child: Text(
        riskLabel(risk),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Always-allow rules: commands Hermes may run without asking, each with a
/// risk label and an optional expiry.
class ApprovalRulesScreen extends StatefulWidget {
  const ApprovalRulesScreen({super.key});
  @override
  State<ApprovalRulesScreen> createState() => _ApprovalRulesScreenState();
}

class _ApprovalRulesScreenState extends State<ApprovalRulesScreen> {
  Future<List<ApprovalRule>>? _rules;
  Wave3Api get _api => Wave3Api.of(HermesMobileScope.read(context).backend);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rules ??= _api.listRules();
  }

  void _reload() => setState(() {
    _rules = _api.listRules();
  });

  Future<void> _run(Future<void> Function() f, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await f();
      m.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) _reload();
  }

  Future<void> _add() async {
    final r = await showModalBottomSheet<(String, DateTime?, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RuleEditor(),
    );
    if (r == null || r.$1.trim().isEmpty) return;
    await _run(
      () => _api.addRule(r.$1.trim(), expiresAt: r.$2, note: r.$3),
      'Hermes can now run “${r.$1.trim()}” without asking',
    );
  }

  /// Rules hidden while their Undo window is open.
  final Set<String> _revoking = {};

  /// Revoke with a 6 s Undo; the server only hears about it afterwards.
  void _remove(ApprovalRule rule) {
    W2Haptics.medium();
    setState(() => _revoking.add(rule.pattern));
    final api = _api;
    showUndoSnackBar(
      context,
      message: 'Hermes will ask before “${rule.pattern}” again',
      onUndo: () {
        if (mounted) setState(() => _revoking.remove(rule.pattern));
      },
      onCommit: () async {
        try {
          await api.removeRule(rule.pattern);
        } catch (e) {
          if (mounted) showHermesMobileSnack(context, 'Could not revoke: $e');
        }
        _revoking.remove(rule.pattern);
        if (mounted) _reload();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Approval rules')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('w3-rule-add'),
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add rule'),
      ),
      body: FutureBuilder<List<ApprovalRule>>(
        future: _rules,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonList(count: 3);
          }
          if (snap.error is PluginMissing) {
            return EmptyState(
              icon: Icons.extension_off_outlined,
              title: 'Needs the Petasos plugin',
              body:
                  'Approval rules are managed by the Petasos plugin on your Hermes '
                  'host. Copy server/hermes_mobile_plugin to ~/.hermes/plugins/hermes_mobile, add '
                  '"hermes_mobile" to plugins.enabled and restart the dashboard. Until '
                  'then, “Always” on an approval prompt still works.',
              action: TextButton(
                onPressed: _reload,
                child: const Text('Check again'),
              ),
            );
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load rules',
              body: '${snap.error}',
              action: TextButton(
                onPressed: _reload,
                child: const Text('Retry'),
              ),
            );
          }
          final rules = snap.data ?? const [];
          final risky = rules
              .where((r) => r.risk == RuleRisk.high && r.expiresAt == null)
              .length;
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _rules;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(
                  'Hermes runs these without asking. Everything else still needs your OK.',
                  style: t.bodySmall,
                ),
                if (risky > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.hermesMobile.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(HermesMobileRadius.card),
                    ),
                    child: Text(
                      '$risky high-risk rule${risky == 1 ? '' : 's'} never expire. '
                      'Consider an expiry.',
                      style: t.bodySmall?.copyWith(color: context.hermesMobile.danger),
                    ),
                  ),
                if (rules.isEmpty)
                  const EmptyState(
                    icon: Icons.verified_user_outlined,
                    title: 'No always-allow rules',
                    body: 'Hermes asks before every risky command.',
                  ),
                for (final r in rules.where(
                  (r) => !_revoking.contains(r.pattern),
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Dismissible(
                      key: ValueKey('rule-${r.pattern}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _remove(r),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: context.hermesMobile.danger,
                        ),
                      ),
                      child: HermesMobileCardFrame(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.pattern,
                                    style: t.bodyMedium?.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                RiskChip(r.risk),
                              ],
                            ),
                            if (r.note != null && r.note!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(r.note!, style: t.bodySmall),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  r.expiresAt == null
                                      ? Icons.all_inclusive_rounded
                                      : Icons.timer_outlined,
                                  size: 14,
                                  color: context.hermesMobile.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    expiryLabel(r),
                                    style: t.labelSmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _remove(r),
                                  child: const Text('Revoke'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor();
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  final _pattern = TextEditingController();
  final _note = TextEditingController();
  Duration? _ttl = const Duration(days: 1);

  static const _options = <(String, Duration?)>[
    ('1 hour', Duration(hours: 1)),
    ('1 day', Duration(days: 1)),
    ('1 week', Duration(days: 7)),
    ('30 days', Duration(days: 30)),
    ('Never', null),
  ];

  @override
  void dispose() {
    _pattern.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final risk = ApprovalRule.riskFor(_pattern.text);
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
          Text('Always allow', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            key: const Key('w3-rule-pattern'),
            controller: _pattern,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'Command, e.g. git push',
            ),
          ),
          if (_pattern.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: RiskChip(risk)),
          ],
          const SizedBox(height: 12),
          Text('Expires after', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, d) in _options)
                ChoiceChip(
                  label: Text(label),
                  selected: _ttl == d,
                  onSelected: (_) => setState(() => _ttl = d),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(hintText: 'Note (optional)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('w3-rule-save'),
            onPressed: () => Navigator.of(context).pop((
              _pattern.text,
              _ttl == null ? null : DateTime.now().add(_ttl!),
              _note.text,
            )),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }
}
