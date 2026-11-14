import 'package:flutter/material.dart';

import '../../cards/card_widgets.dart';
import '../../data/app_state.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'approval_rules_screen.dart';
import 'cron_studio_screen.dart';
import 'live_run_screen.dart';
import 'memory_manager_screen.dart';
import 'usage_meter_screen.dart';

/// The "Control and trust" group on the Profile screen (Wave 3).
class Wave3SettingsSection extends StatelessWidget {
  const Wave3SettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final state = HermesMobileScope.of(context);
    void push(Widget w) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HermesMobileScope(state: state, child: w)),
    );
    final rows = <(IconData, String, String, VoidCallback)>[
      (
        Icons.monitor_heart_outlined,
        'Live run',
        'Steps, files, commands; pause, steer, take over',
        () {
          final ctl = state.current;
          if (ctl == null) return;
          openLiveRun(context, ctl);
        },
      ),
      (
        Icons.event_repeat_rounded,
        'Cron studio',
        'Run history, last output, failures, rerun',
        () => push(const CronStudioScreen()),
      ),
      (
        Icons.psychology_alt_outlined,
        'Memory manager',
        'Edit, pin, forget; incognito chats',
        () => push(const MemoryManagerScreen()),
      ),
      (
        Icons.verified_user_outlined,
        'Approval rules',
        'Always-allow list with expiry and risk',
        () => push(const ApprovalRulesScreen()),
      ),
      (
        Icons.savings_outlined,
        'Cost and budget',
        'Spend this month and budget alert',
        () => push(const UsageMeterScreen()),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BudgetAlertBanner(onTap: () => push(const UsageMeterScreen())),
        const SectionHeader('Control and trust'),
        HermesMobileCardFrame(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 52, color: c.hairline),
                ListTile(
                  key: Key('w3-row-$i'),
                  leading: Icon(rows[i].$1, size: 22),
                  title: Text(rows[i].$2),
                  subtitle: Text(
                    rows[i].$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: rows[i].$4,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
