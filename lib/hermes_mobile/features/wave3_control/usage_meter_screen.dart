import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cards/card_widgets.dart';
import '../../data/app_state.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'wave3_api.dart';
import 'wave3_models.dart';

/// A monthly spend budget kept on the phone.
class UsageBudget {
  const UsageBudget({this.monthlyUsd, this.alertPct = 80});
  final double? monthlyUsd;
  final int alertPct;

  static const _kBudget = 'hermes_mobile.w3.budget_usd';
  static const _kPct = 'hermes_mobile.w3.budget_alert_pct';

  static Future<UsageBudget> load() async {
    final p = await SharedPreferences.getInstance();
    return UsageBudget(
      monthlyUsd: p.getDouble(_kBudget),
      alertPct: p.getInt(_kPct) ?? 80,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    if (monthlyUsd == null) {
      await p.remove(_kBudget);
    } else {
      await p.setDouble(_kBudget, monthlyUsd!);
    }
    await p.setInt(_kPct, alertPct);
  }
}

enum BudgetLevel { none, ok, warn, over, forecastOver }

/// Where spend stands against the budget.
BudgetLevel budgetLevel(UsageWindow u, UsageBudget b, DateTime now) {
  final cap = b.monthlyUsd;
  if (cap == null || cap <= 0) return BudgetLevel.none;
  final mtd = u.monthToDate(now);
  if (mtd >= cap) return BudgetLevel.over;
  if (mtd >= cap * b.alertPct / 100) return BudgetLevel.warn;
  if (u.forecastMonth(now) > cap) return BudgetLevel.forecastOver;
  return BudgetLevel.ok;
}

String budgetMessage(BudgetLevel l, UsageWindow u, UsageBudget b, DateTime now) {
  final mtd = u.monthToDate(now).toStringAsFixed(2);
  final cap = b.monthlyUsd?.toStringAsFixed(2) ?? '—';
  return switch (l) {
    BudgetLevel.over => 'Over budget: \$$mtd of \$$cap this month.',
    BudgetLevel.warn => '${(u.monthToDate(now) / b.monthlyUsd! * 100).round()}% of your \$$cap budget used.',
    BudgetLevel.forecastOver =>
      'On pace for \$${u.forecastMonth(now).toStringAsFixed(2)} this month, over your \$$cap budget.',
    BudgetLevel.ok => '\$$mtd of \$$cap this month.',
    BudgetLevel.none => 'No budget set.',
  };
}

/// Small banner for Settings: shows only when spend needs attention.
class BudgetAlertBanner extends StatelessWidget {
  const BudgetAlertBanner({super.key, this.now, this.onTap});
  final DateTime? now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final api = Wave3Api.of(HermesMobileScope.of(context).backend);
    return FutureBuilder<(UsageWindow?, UsageBudget)>(
      future: () async {
        final b = await UsageBudget.load();
        if (b.monthlyUsd == null) return (null, b);
        try {
          return (await api.usageWindow(), b);
        } catch (_) {
          return (null, b);
        }
      }(),
      builder: (context, snap) {
        final d = snap.data;
        final u = d?.$1;
        if (u == null) return const SizedBox.shrink();
        final n = now ?? DateTime.now();
        final level = budgetLevel(u, d!.$2, n);
        if (level == BudgetLevel.ok || level == BudgetLevel.none) {
          return const SizedBox.shrink();
        }
        final c = context.hermesMobile;
        final color = level == BudgetLevel.over ? c.danger : c.warning;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(HermesMobileRadius.card),
            child: InkWell(
              key: const Key('w3-budget-banner'),
              borderRadius: BorderRadius.circular(HermesMobileRadius.card),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.savings_outlined, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        budgetMessage(level, u, d.$2, n),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cost and usage meter with a monthly budget and alert threshold.
class UsageMeterScreen extends StatefulWidget {
  const UsageMeterScreen({super.key, this.now});
  final DateTime? now;
  @override
  State<UsageMeterScreen> createState() => _UsageMeterScreenState();
}

class _UsageMeterScreenState extends State<UsageMeterScreen> {
  Future<(UsageWindow?, UsageBudget)>? _data;

  Future<(UsageWindow?, UsageBudget)> _load() async {
    final api = Wave3Api.of(HermesMobileScope.read(context).backend);
    final b = await UsageBudget.load();
    return (await api.usageWindow(), b);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _editBudget(UsageBudget b) async {
    final r = await showModalBottomSheet<UsageBudget>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BudgetEditor(budget: b),
    );
    if (r == null) return;
    await r.save();
    if (mounted) _reload();
  }

  String _n(int? v) {
    if (v == null) return '—';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final now = widget.now ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Cost and usage')),
      body: FutureBuilder<(UsageWindow?, UsageBudget)>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonList(count: 3);
          }
          final u = snap.data?.$1;
          if (snap.hasError || u == null) {
            return EmptyState(
              icon: Icons.insights_outlined,
              title: 'Usage unavailable',
              body: 'Usage comes from the dashboard analytics.\n${snap.error ?? ''}',
              action: TextButton(onPressed: _reload, child: const Text('Retry')),
            );
          }
          final b = snap.data!.$2;
          final level = budgetLevel(u, b, now);
          final mtd = u.monthToDate(now);
          final forecast = u.forecastMonth(now);
          final cap = b.monthlyUsd;
          final frac = cap == null || cap <= 0 ? null : (mtd / cap).clamp(0.0, 1.0);
          final barColor = switch (level) {
            BudgetLevel.over => c.danger,
            BudgetLevel.warn || BudgetLevel.forecastOver => c.warning,
            _ => c.accent,
          };
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _data;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                HermesMobileCardFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('This month', style: t.labelMedium),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${mtd.toStringAsFixed(2)}',
                            key: const Key('w3-mtd'),
                            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          if (cap != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('of \$${cap.toStringAsFixed(0)}', style: t.bodySmall),
                            ),
                          const Spacer(),
                          TextButton(
                            key: const Key('w3-budget-edit'),
                            onPressed: () => _editBudget(b),
                            child: Text(cap == null ? 'Set budget' : 'Edit'),
                          ),
                        ],
                      ),
                      if (frac != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: frac,
                            minHeight: 8,
                            color: barColor,
                            backgroundColor: c.surfaceMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Forecast \$${forecast.toStringAsFixed(2)} by month end'
                        '${cap == null ? '' : ' · alert at ${b.alertPct}%'}',
                        style: t.bodySmall,
                      ),
                      if (level != BudgetLevel.ok && level != BudgetLevel.none) ...[
                        const SizedBox(height: 8),
                        Text(
                          budgetMessage(level, u, b, now),
                          key: const Key('w3-budget-alert'),
                          style: t.bodySmall?.copyWith(
                            color: barColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (u.daily.isNotEmpty) ...[
                  SectionHeader(
                    'Daily cost · ${u.days} days',
                    trailing: Text('\$${u.costUsd.toStringAsFixed(2)} total', style: t.labelSmall),
                  ),
                  HermesMobileCardFrame(child: _DailyBars(daily: u.daily, color: c.accent)),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _Tile('Sessions', _n(u.sessions))),
                    const SizedBox(width: 10),
                    Expanded(child: _Tile('Input', _n(u.inputTokens))),
                    const SizedBox(width: 10),
                    Expanded(child: _Tile('Output', _n(u.outputTokens))),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Costs are Hermes’ own estimates (or the provider’s actual cost when it reports one). '
                  'The budget lives on this phone.',
                  style: t.labelSmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return HermesMobileCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.daily, required this.color});
  final List<MapEntry<DateTime, double>> daily;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final max = daily.fold(0.0, (a, e) => e.value > a ? e.value : a);
    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in daily)
            Expanded(
              child: Tooltip(
                message: '${e.key.month}/${e.key.day}: \$${e.value.toStringAsFixed(2)}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: max <= 0 ? 2 : (e.value / max * 86).clamp(2.0, 86.0),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({required this.budget});
  final UsageBudget budget;
  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late final _amount = TextEditingController(
    text: widget.budget.monthlyUsd?.toStringAsFixed(0) ?? '',
  );
  late double _pct = widget.budget.alertPct.toDouble();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Monthly budget', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            key: const Key('w3-budget-field'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '\$ ', hintText: 'e.g. 25'),
          ),
          const SizedBox(height: 12),
          Text('Alert at ${_pct.round()}%', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: _pct,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_pct.round()}%',
            onChanged: (v) => setState(() => _pct = v),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(
                  UsageBudget(monthlyUsd: null, alertPct: _pct.round()),
                ),
                child: const Text('No budget'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('w3-budget-save'),
                onPressed: () {
                  final v = double.tryParse(_amount.text.trim());
                  Navigator.of(context).pop(
                    UsageBudget(
                      monthlyUsd: v != null && v > 0 ? v : null,
                      alertPct: _pct.round(),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
