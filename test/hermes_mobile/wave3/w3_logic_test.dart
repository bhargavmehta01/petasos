import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/cron_studio_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/memory_manager_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/run_insights.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/usage_meter_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/wave3_api.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/wave3_demo_api.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/wave3_models.dart';

void main() {
  test('risk labels match the plugin heuristic', () {
    expect(ApprovalRule.riskFor('rm -rf build'), RuleRisk.high);
    expect(ApprovalRule.riskFor('sudo systemctl restart x'), RuleRisk.high);
    expect(ApprovalRule.riskFor('git push origin main'), RuleRisk.medium);
    expect(ApprovalRule.riskFor('ls -la'), RuleRisk.low);
    final r = ApprovalRule.fromJson({
      'pattern': 'ls',
      'risk': 'high',
      'expires_at': 1,
    });
    expect(r.risk, RuleRisk.high);
    expect(r.isExpired(), isTrue);
  });

  test('run insights pull commands and files from steps', () {
    final steps = [
      HermesMobileStep(id: '1', label: 'terminal', detail: 'journalctl -u hermes-cron'),
      HermesMobileStep(id: '2', label: 'patch', detail: 'scripts/panels_publish.sh'),
      HermesMobileStep(id: '3', label: 'read file', detail: 'scripts/panels_publish.sh'),
      HermesMobileStep(id: '4', label: 'read file', detail: 'README.md'),
      HermesMobileStep(id: '5', label: 'web search', detail: 'hermes cron docs'),
      HermesMobileStep(id: '6', label: 'terminal', detail: 'journalctl -u hermes-cron'),
    ];
    final i = RunInsights.fromSteps(steps);
    expect(i.commands, ['journalctl -u hermes-cron']);
    expect(i.filesChanged, ['scripts/panels_publish.sh']);
    expect(i.filesRead, ['README.md']);
    expect(i.web, ['hermes cron docs']);
    expect(steerPrompt('use rsync'), contains('use rsync'));
    expect(handBackPrompt(''), contains('took over'));
  });

  test('usage window parses dashboard analytics and forecasts', () {
    final u = LiveWave3Api.parseUsageWindow({
      'daily': [
        {'day': '2026-11-01', 'estimated_cost': 1.0, 'actual_cost': 0},
        {'day': '2026-11-02', 'estimated_cost': 2.0, 'actual_cost': 3.0},
        {'day': '2026-10-31', 'estimated_cost': 5.0},
      ],
      'totals': {
        'total_estimated_cost': 8.0,
        'total_actual_cost': 0,
        'total_sessions': 4,
        'total_input': 100,
      },
    });
    expect(u.costUsd, 8.0);
    expect(u.daily.first.key, DateTime(2026, 10, 31));
    final now = DateTime(2026, 11, 2);
    expect(u.monthToDate(now), 4.0);
    expect(u.forecastMonth(now), closeTo(60.0, 0.001));
    expect(u.sessions, 4);

    const b = UsageBudget(monthlyUsd: 50, alertPct: 80);
    expect(budgetLevel(u, b, now), BudgetLevel.forecastOver);
    expect(budgetLevel(u, const UsageBudget(monthlyUsd: 4.5), now), BudgetLevel.warn);
    expect(budgetLevel(u, const UsageBudget(monthlyUsd: 3), now), BudgetLevel.over);
    expect(budgetLevel(u, const UsageBudget(), now), BudgetLevel.none);
  });

  test('cron run rows and health', () {
    final bad = LiveWave3Api.parseCronRun({
      'id': 'cron_x_1',
      'started_at': 1762180000,
      'ended_at': 1762180060,
      'end_reason': 'error',
    });
    expect(bad.ok, isFalse);
    expect(bad.duration, const Duration(minutes: 1));
    final good = LiveWave3Api.parseCronRun({
      'id': 'cron_x_2',
      'started_at': 1762180000,
      'ended_at': 1762180010,
    });
    expect(good.ok, isTrue);
    const job = HermesMobileCronJob(id: 'x', name: 'X', schedule: '', prompt: '');
    expect(cronHealth(job), CronHealth.unknown);
    expect(cronHealth(job, CronJobDetail(runs: [bad])), CronHealth.failing);
    expect(cronHealth(job, CronJobDetail(runs: [good])), CronHealth.healthy);
    const paused = HermesMobileCronJob(id: 'p', name: 'P', schedule: '', prompt: '', paused: true);
    expect(cronHealth(paused), CronHealth.paused);
  });

  test('demo api: memory, rules and provenance', () async {
    final api = DemoWave3Api(fixedNow: DateTime(2026, 11, 3, 12));
    final mem = await api.listMemory();
    expect(mem.first.pinned, isTrue);
    expect(provenanceLine(mem.first), contains('Saved by Hermes'));
    final added = await api.addMemory(MemoryTarget.memory, 'Car: Grand Highlander');
    await api.setPinned(added, true);
    expect((await api.listMemory()).where((e) => e.pinned), hasLength(2));
    await api.deleteMemory(added);
    expect((await api.listMemory()).any((e) => e.id == added.id), isFalse);
    await api.setIncognito('c1', true);
    expect(await api.incognitoChats(), {'c1'});

    final rules = await api.listRules();
    expect(rules.first.risk, RuleRisk.high);
    await api.addRule('npm test', expiresAt: DateTime(2026, 11, 3, 13));
    expect((await api.listRules()).any((r) => r.pattern == 'npm test'), isTrue);
    await api.removeRule('npm test');
    expect((await api.listRules()).any((r) => r.pattern == 'npm test'), isFalse);
  });
}
