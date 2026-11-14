import 'dart:async';

import 'backend.dart';
import 'models.dart';
import 'panels.dart';

/// A fake Hermes with sample chats, cards and panels so every screen can be
/// reviewed without a server. Enable with `--dart-define=HERMES_MOBILE_DEMO=true` or
/// "Explore the demo" on the connect screen.
class DemoBackend implements HermesMobileBackend {
  DemoBackend({this.fast = false});

  /// Tests use fast mode: no artificial streaming delays.
  final bool fast;
  final Map<String, List<HermesMobileMessage>> _messages = {};
  final List<HermesMobileChat> _chats = [];
  final Map<String, Completer<String>> _approvalWaits = {};
  final Set<String> _stopped = {};
  int _seq = 0;
  final List<HermesMobileCronJob> _cron = [
    const HermesMobileCronJob(
      id: 'brief',
      name: 'Morning brief',
      schedule: 'Every day at 7:00',
      prompt: 'Summarise my calendar, weather and overnight email.',
      nextRun: 'Tomorrow 7:00',
      lastStatus: 'ok',
    ),
    const HermesMobileCronJob(
      id: 'backup',
      name: 'Nightly backup check',
      schedule: '0 3 * * *',
      prompt: 'Verify last night\'s restic and B2 backups and report.',
      nextRun: 'Tonight 3:00',
      lastStatus: 'ok',
    ),
    const HermesMobileCronJob(
      id: 'prices',
      name: 'Price watch',
      schedule: 'Every 6 hours',
      prompt: 'Check watched items and update the price-watch panel.',
      paused: true,
    ),
  ];

  static final DateTime _now = DateTime.now();

  static const sampleReply =
      '''Here's what I found for **Springfield weekend options**.

**This weekend**
| Event | Day | Price |
|---|---|---|
| City Botanical Garden lights | Sat | \$34 |
| Ponce City Market rooftop | Sat–Sun | Free entry |
| Braves Fest | Sun | \$15 |

Sources:
- [City Botanical Garden](https://example.org/garden/)
- [Ponce City Market](https://poncecitymarket.com/)
- [Springfield events](https://example.com/events/)

```hermes-mobile-card
{"type":"calendar","title":"Garden lights with Maya","start":"2026-11-07T18:30:00-05:00","end":"2026-11-07T20:30:00-05:00","location":"100 Garden Way, Springfield"}
```

Want me to book the garden tickets?''';

  static const orderReply =
      '''Your cart is ready. Nothing is charged until you approve.

```hermes-mobile-card
{"type":"order_summary","merchant":"Costco Same-Day","status":"Ready","items":[{"name":"Kirkland Organic Milk 3-pack","qty":1,"price":13.99},{"name":"Bananas","qty":2,"price":1.99},{"name":"Rotisserie chicken","qty":1,"price":4.99}],"subtotal":22.96,"fees":3.99,"total":26.95,"note":"Delivery today 5–6 pm","approve_label":"Approve and order"}
```''';

  static const codeReply =
      '''The cron script failed because `jq` was missing on the host. I patched it:

```bash
#!/usr/bin/env bash
set -euo pipefail
command -v jq >/dev/null || sudo apt-get install -y jq
python3 ~/.hermes/scripts/panels_publish.py --all
```

```hermes-mobile-card
{"type":"summary","title":"Full fix log","markdown":"1. Reproduced the failure with `bash -x`.\\n2. Found `jq: command not found` on line 14.\\n3. Added a guard that installs `jq`.\\n4. Re-ran: **all 6 panels published**.\\n5. Merged to `agent-stack/main` (commit 4f2a9c1)."}
```

MEDIA:/home/bhargav/.hermes/logs/selfheal-2026-11-03.log''';

  void _seed() {
    if (_chats.isNotEmpty) return;
    void add(
      String id,
      String title,
      Duration ago,
      List<HermesMobileMessage> msgs, {
      bool active = false,
    }) {
      _chats.add(
        HermesMobileChat(
          id: id,
          title: title,
          preview: msgs.isEmpty ? '' : msgs.last.text,
          updatedAt: _now.subtract(ago),
          isActive: active,
          messageCount: msgs.length,
        ),
      );
      _messages[id] = msgs;
    }

    add('demo-weekend', 'Weekend plans', const Duration(minutes: 12), [
      HermesMobileMessage(
        role: HermesMobileRole.user,
        text: 'What can we do in Springfield this weekend with a toddler?',
      ),
      HermesMobileMessage(
        role: HermesMobileRole.assistant,
        text: sampleReply,
        toolNames: const ['web_search', 'web_extract', 'calendar_lookup'],
      ),
    ]);
    add('demo-groceries', 'Costco restock', const Duration(hours: 2), [
      HermesMobileMessage(
        role: HermesMobileRole.user,
        text: 'Restock milk, bananas and a chicken.',
      ),
      HermesMobileMessage(
        role: HermesMobileRole.assistant,
        text: orderReply,
        toolNames: const [
          'browser_navigate',
          'browser_click',
          'browser_snapshot',
        ],
      ),
    ]);
    add('demo-cron', 'Fix the panels cron', const Duration(hours: 5), [
      HermesMobileMessage(
        role: HermesMobileRole.user,
        text: 'The panels cron failed again. Fix it.',
      ),
      HermesMobileMessage(
        role: HermesMobileRole.assistant,
        text: codeReply,
        toolNames: const ['terminal', 'read_file', 'patch', 'terminal'],
      ),
    ]);
    add('demo-research', 'Home EV charger research', const Duration(days: 1), [
      HermesMobileMessage(
        role: HermesMobileRole.user,
        text: 'Compare level 2 chargers for the garage.',
      ),
      HermesMobileMessage(
        role: HermesMobileRole.assistant,
        text:
            '''Short version: get the **ChargePoint Home Flex** unless you want a cheaper hardwired unit.

| Charger | Max amps | Price | Smart app |
|---|---|---|---|
| ChargePoint Home Flex | 50 A | \$549 | Yes |
| Emporia Classic | 48 A | \$399 | Yes |
| Grizzl-E Classic | 40 A | \$349 | No |
| Tesla Universal | 48 A | \$595 | Yes |

https://www.chargepoint.com/drivers/home
https://www.emporiaenergy.com/ev-charger''',
        toolNames: const ['web_search', 'web_search', 'web_extract'],
      ),
    ]);
    add('demo-running', 'Nightly backup audit', const Duration(minutes: 1), [
      HermesMobileMessage(role: HermesMobileRole.user, text: 'Audit last night\'s backups.'),
    ], active: true);
  }

  @override
  bool get isDemo => true;

  @override
  ConnectionSummary get connection => const ConnectionSummary(
    label: 'Demo Hermes',
    endpoint: 'demo://hermes',
    dashboard: 'demo://dashboard',
    healthy: true,
  );

  Future<void> _wait(int ms) => fast
      ? Future<void>.value()
      : Future<void>.delayed(Duration(milliseconds: ms));

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<List<HermesMobileChat>> listChats() async {
    _seed();
    await _wait(250);
    final list = List.of(_chats)
      ..sort((a, b) => (b.updatedAt ?? _now).compareTo(a.updatedAt ?? _now));
    return list;
  }

  @override
  Future<List<HermesMobileChat>> searchChats(String query) async {
    final q = query.toLowerCase();
    final all = await listChats();
    return all
        .where(
          (c) =>
              c.displayTitle.toLowerCase().contains(q) ||
              (_messages[c.id] ?? const []).any(
                (m) => m.text.toLowerCase().contains(q),
              ),
        )
        .toList();
  }

  @override
  Future<List<HermesMobileMessage>> loadMessages(String chatId) async {
    _seed();
    await _wait(300);
    return List.of(_messages[chatId] ?? const []);
  }

  @override
  String newChatId() => 'demo-new-${++_seq}';

  @override
  Future<void> renameChat(String chatId, String title) async {
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i >= 0) _chats[i] = _chats[i].copyWith(title: title);
  }

  final List<HermesMobileChat> _archived = [];

  @override
  Future<void> setChatArchived(String chatId, bool archived) async {
    if (archived) {
      final hit = _chats.where((c) => c.id == chatId).toList();
      _chats.removeWhere((c) => c.id == chatId);
      _archived.insertAll(0, hit);
    } else {
      final hit = _archived.where((c) => c.id == chatId).toList();
      _archived.removeWhere((c) => c.id == chatId);
      _chats.addAll(hit);
    }
  }

  @override
  Future<List<HermesMobileChat>> listArchivedChats() async => List.of(_archived);

  @override
  Future<void> deleteChat(String chatId) async {
    _chats.removeWhere((c) => c.id == chatId);
    _messages.remove(chatId);
  }

  @override
  Future<void> send({
    required String chatId,
    required String text,
    required List<Map<String, dynamic>> history,
    String? imageDataUrl,
    required HermesMobileTurnCallbacks callbacks,
  }) async {
    _seed();
    _stopped.remove(chatId);
    bool stopped() => _stopped.contains(chatId);
    final lower = text.toLowerCase();
    callbacks.onStatus({'text': 'Thinking…'});
    callbacks.onReasoning('The user asked: "$text". Plan the steps first. ');
    await _wait(500);

    final tools = <(String, String, String)>[
      ('t1', 'web_search', 'springfield weekend events toddler'),
      ('t2', 'web_extract', 'example.org'),
    ];
    if (lower.contains('order') ||
        lower.contains('buy') ||
        lower.contains('costco')) {
      tools
        ..clear()
        ..addAll([
          ('t1', 'browser_navigate', 'costco.com/same-day'),
          ('t2', 'browser_click', 'Add to cart'),
        ]);
    }
    if (lower.contains('fix') ||
        lower.contains('cron') ||
        lower.contains('deploy') ||
        lower.contains('delete')) {
      tools
        ..clear()
        ..addAll([
          ('t1', 'terminal', 'journalctl -u hermes-cron --since today'),
          ('t2', 'patch', 'scripts/panels_publish.sh'),
        ]);
    }
    for (final (id, name, detail) in tools) {
      if (stopped()) return;
      callbacks.onTool({
        'tool': name,
        'name': name,
        'tool_call_id': id,
        'status': 'running',
        'preview': detail,
        'label': detail,
      });
      await _wait(700);
      callbacks.onTool({
        'tool': name,
        'name': name,
        'tool_call_id': id,
        'status': 'completed',
        'preview': detail,
        'label': detail,
        'duration': 0.7,
      });
    }

    // --- wave1 ---
    final prompt = wave1DemoPrompt(lower);
    if (prompt != null) {
      final wait = Completer<String>();
      _promptWaits[chatId] = wait;
      callbacks.onStatus(prompt);
      final answer = await wait.future;
      if (stopped()) return;
      final said = prompt['hermes_mobile_control'] == 'clarify.request'
          ? 'Got it: **$answer**. '
          : 'Thanks, I used it once and did not store it. ';
      await _streamText(callbacks, '${said}Carrying on with "$text".', stopped);
      if (!stopped()) callbacks.onDone();
      return;
    }
    // --- end wave1 ---
    if (lower.contains('deploy') ||
        lower.contains('delete') ||
        lower.contains('approve')) {
      final wait = Completer<String>();
      _approvalWaits[chatId] = wait;
      callbacks.onApproval({
        'command': 'sudo systemctl restart hermes-gateway',
        'description': 'Restart the gateway so the patched cron script loads.',
        'run_id': 'demo-run',
        'request_id': 'demo-approval',
        'choices': ['once', 'session', 'always', 'deny'],
      });
      final choice = await wait.future;
      if (choice == 'deny') {
        await _streamText(
          callbacks,
          "Okay, I won't restart it. The fix is staged and will load on the next restart.",
          stopped,
        );
        if (!stopped()) callbacks.onDone();
        return;
      }
      callbacks.onTool({
        'tool': 'terminal',
        'tool_call_id': 't3',
        'status': 'completed',
        'preview': 'sudo systemctl restart hermes-gateway',
      });
    }

    final reply =
        lower.contains('order') ||
            lower.contains('costco') ||
            lower.contains('buy')
        ? orderReply
        : (lower.contains('fix') ||
              lower.contains('cron') ||
              lower.contains('deploy'))
        ? codeReply
        : lower.contains('weekend') || lower.contains('springfield')
        ? sampleReply
        : 'Done. Here is a quick summary:\n\n- I looked at **"$text"**.\n- Nothing needs your attention right now.\n\nhttps://hermes-agent.nousresearch.com/docs';
    await _streamText(callbacks, reply, stopped);
    if (stopped()) return;
    final msgs = _messages.putIfAbsent(chatId, () => []);
    msgs
      ..add(HermesMobileMessage(role: HermesMobileRole.user, text: text))
      ..add(HermesMobileMessage(role: HermesMobileRole.assistant, text: reply));
    if (!_chats.any((c) => c.id == chatId)) {
      _chats.add(
        HermesMobileChat(
          id: chatId,
          title: text.length > 40 ? '${text.substring(0, 40)}…' : text,
          preview: reply,
          updatedAt: DateTime.now(),
        ),
      );
    }
    callbacks.onDone();
  }

  Future<void> _streamText(
    HermesMobileTurnCallbacks callbacks,
    String reply,
    bool Function() stopped,
  ) async {
    if (fast) {
      callbacks.onToken(reply);
      return;
    }
    final words = RegExp(r'\S+\s*|\s+').allMatches(reply).map((m) => m[0]!);
    var buffer = StringBuffer();
    var n = 0;
    for (final w in words) {
      if (stopped()) return;
      buffer.write(w);
      if (++n % 4 == 0) {
        callbacks.onToken(buffer.toString());
        buffer = StringBuffer();
        await _wait(40);
      }
    }
    if (buffer.isNotEmpty) callbacks.onToken(buffer.toString());
  }

  // --- wave1 ---
  final Map<String, Completer<String>> _promptWaits = {};

  /// Answers the demo's pending sudo/secret/clarify prompt for [chatId].
  void wave1AnswerPrompt(String chatId, String value) =>
      _promptWaits.remove(chatId)?.complete(value);

  /// Demo prompts: "sudo …", "secret / api key …", "which / clarify …".
  static Map<String, dynamic>? wave1DemoPrompt(String lower) {
    if (lower.contains('sudo')) {
      return {
        'hermes_mobile_control': 'sudo.request',
        'request_id': 'demo-sudo',
        'run_id': 'demo-run',
      };
    }
    if (lower.contains('api key') || lower.contains('secret')) {
      return {
        'hermes_mobile_control': 'secret.request',
        'request_id': 'demo-secret',
        'env_var': 'OPENWEATHER_API_KEY',
        'prompt': 'The weather skill needs an OpenWeather API key.',
        'run_id': 'demo-run',
      };
    }
    if (lower.contains('clarify') || lower.startsWith('which ')) {
      return {
        'hermes_mobile_control': 'clarify.request',
        'request_id': 'demo-clarify',
        'run_id': 'demo-run',
        'questions': [
          {
            'qid': 'q1',
            'question': 'Which calendar should I use?',
            'choices': ['Family', 'Work', 'Both'],
          },
        ],
      };
    }
    return null;
  }
  // --- end wave1 ---

  @override
  Future<bool> stop(String chatId) async {
    _promptWaits.remove(chatId)?.complete(''); // wave1
    _stopped.add(chatId);
    _approvalWaits.remove(chatId)?.complete('deny');
    return true;
  }

  @override
  Future<void> answerApproval(HermesMobileApproval approval, String choice) async {
    _approvalWaits.remove(approval.chatId)?.complete(choice);
  }

  @override
  Future<List<HermesMobileProject>?> listProjects() async {
    await _wait(200);
    return const [
      HermesMobileProject(
        id: 'p-hermes_mobile',
        name: 'Petasos app',
        description: 'Android reskin',
        path: '~/code/petasos',
        chatCount: 2,
      ),
      HermesMobileProject(
        id: 'p-home',
        name: 'Home lab',
        description: 'OCI box, backups, Tailscale',
        path: '~/agent-stack',
        chatCount: 1,
      ),
    ];
  }

  @override
  Future<List<HermesMobileChat>> projectChats(String projectId) async {
    final all = await listChats();
    return projectId == 'p-home'
        ? all.where((c) => c.id == 'demo-cron').toList()
        : all.where((c) => c.id == 'demo-research').toList();
  }

  @override
  Future<List<HermesMobileCronJob>> listCron() async {
    await _wait(250);
    return List.of(_cron);
  }

  @override
  Future<void> createCron({
    required String name,
    required String schedule,
    required String prompt,
  }) async {
    _cron.add(
      HermesMobileCronJob(
        id: 'c${++_seq}',
        name: name,
        schedule: schedule,
        prompt: prompt,
      ),
    );
  }

  @override
  Future<void> updateCron(String id, Map<String, dynamic> updates) async {
    final i = _cron.indexWhere((j) => j.id == id);
    if (i < 0) return;
    final j = _cron[i];
    _cron[i] = HermesMobileCronJob(
      id: j.id,
      name: updates['name']?.toString() ?? j.name,
      schedule: updates['schedule']?.toString() ?? j.schedule,
      prompt: updates['prompt']?.toString() ?? j.prompt,
      paused: j.paused,
      nextRun: j.nextRun,
      lastStatus: j.lastStatus,
    );
  }

  @override
  Future<void> setCronPaused(String id, bool paused) async {
    final i = _cron.indexWhere((j) => j.id == id);
    if (i < 0) return;
    final j = _cron[i];
    _cron[i] = HermesMobileCronJob(
      id: j.id,
      name: j.name,
      schedule: j.schedule,
      prompt: j.prompt,
      paused: paused,
      nextRun: j.nextRun,
      lastStatus: j.lastStatus,
    );
  }

  @override
  Future<void> runCron(String id) async {}

  @override
  Future<void> deleteCron(String id) async =>
      _cron.removeWhere((j) => j.id == id);

  final Map<String, bool> _skillEnabled = {};
  final Map<String, String> _memoryEdits = {};

  static const _demoSkills = [
    HermesMobileSkill(
      name: 'browser',
      description: 'Drive a real browser.',
      category: 'web',
      provenance: 'bundled',
      usage: 41,
    ),
    HermesMobileSkill(
      name: 'google-workspace',
      description: 'Gmail, Calendar and Drive.',
      category: 'productivity',
      provenance: 'hub',
      usage: 18,
    ),
    HermesMobileSkill(
      name: 'hermes-mobile-cards',
      description: 'Reply with structured cards for the phone.',
      category: 'ui',
      provenance: 'agent',
      usage: 7,
    ),
    HermesMobileSkill(
      name: 'home-panels',
      description: 'Publish status panels to Home.',
      category: 'ui',
      provenance: 'agent',
      usage: 3,
    ),
    HermesMobileSkill(
      name: 'github',
      description: 'PRs, issues and CI.',
      category: 'dev',
      provenance: 'bundled',
      usage: 12,
      enabled: false,
    ),
  ];

  @override
  Future<List<HermesMobileSkill>> listSkills() async {
    await _wait(200);
    return [
      for (final s in _demoSkills)
        s.copyWith(enabled: _skillEnabled[s.name] ?? s.enabled),
    ];
  }

  @override
  Future<HermesMobileSkillDetail> skillDetail(String name) async {
    await _wait(150);
    final s = _demoSkills.firstWhere(
      (s) => s.name == name,
      orElse: () => HermesMobileSkill(name: name),
    );
    final content = demoSkillMarkdown(s);
    return HermesMobileSkillDetail(
      content: content,
      path:
          '~/.hermes/skills/${s.category.isEmpty ? '' : '${s.category}/'}${s.name}/SKILL.md',
      files: HermesMobileSkillDetail.linkedFiles(content),
    );
  }

  /// Sample SKILL.md so the detail screen has something real to render.
  static String demoSkillMarkdown(HermesMobileSkill s) =>
      '''---
name: ${s.name}
description: ${s.description}
version: 1.2.0
metadata:
  hermes:
    tags: [${s.category}]
---

# ${s.name}

${s.description} This is a sample skill shown in demo mode.

## When to use

- The user asks for something this skill covers.
- A task needs **${s.category.isEmpty ? 'general' : s.category}** tools.

## Steps

1. Read [the reference guide](references/guide.md) first.
2. Run `scripts/check.sh` to confirm the tool is ready.
3. Report the result in one short message.

## Pitfalls

> Never guess an endpoint. Load the reference first.
''';

  @override
  Future<void> setSkillEnabled(String name, bool enabled) async {
    await _wait(150);
    _skillEnabled[name] = enabled;
  }

  static const _demoMemory = [
    HermesMobileMemoryItem(
      id: 'demo:profile:0',
      title: 'Lives in Springfield',
      scope: 'USER.md',
      body:
          'Lives in Springfield. Pixel 9. Prefers short answers with a clear pick.',
    ),
    HermesMobileMemoryItem(
      id: 'demo:profile:1',
      title: 'Comparisons',
      scope: 'USER.md',
      truncated: true,
      body: '## Comparisons\nWants the full field surveyed, with a clear pick…',
    ),
    HermesMobileMemoryItem(
      id: 'demo:memory:0',
      title: 'Nightly backups go to B2 at 03:00',
      scope: 'MEMORY.md',
      body:
          'Nightly backups go to B2 at 03:00. Panels live in ~/.hermes/panels.',
    ),
  ];

  static const _demoFullText = {
    'demo:profile:1': '''## Comparisons
Wants the full field surveyed, with a clear pick at the top.

- Include open and local models, not only the ones he named.
- Say the downside of the pick in one line.
- Prefer a table when there are more than three options.''',
  };

  @override
  Future<List<HermesMobileMemoryItem>> listMemory() async {
    await _wait(200);
    return [
      for (final m in _demoMemory)
        _memoryEdits.containsKey(m.id)
            ? HermesMobileMemoryItem(
                id: m.id,
                scope: m.scope,
                title: HermesMobileMemoryItem.titleFrom(_memoryEdits[m.id]!),
                body: _memoryEdits[m.id]!,
              )
            : m,
    ];
  }

  @override
  Future<String> memoryFullText(HermesMobileMemoryItem item) async {
    await _wait(120);
    return _memoryEdits[item.id] ?? _demoFullText[item.id] ?? item.body;
  }

  @override
  Future<void> editMemoryItem(HermesMobileMemoryItem item, String content) async {
    await _wait(150);
    _memoryEdits[item.id ?? item.title] = content;
  }

  @override
  Future<HermesMobileUsage?> usage() async => const HermesMobileUsage(
    sessions: 142,
    inputTokens: 4820000,
    outputTokens: 612000,
    costUsd: 18.42,
    topModels: [
      MapEntry('deepseek-v4-flash', 3100000),
      MapEntry('claude-sonnet-4.5', 1900000),
      MapEntry('gpt-5-mini', 420000),
    ],
  );

  static final demoPanels = [
    HermesMobilePanel(
      id: 'daily-cost',
      title: 'API spend · month',
      kind: PanelKind.stat,
      value: '18.42',
      unit: 'USD',
      trend: '+1.37 today',
      subtitle: 'all provider keys',
      updatedAt: _now.subtract(const Duration(minutes: 20)),
      source: 'costs.py',
    ),
    HermesMobilePanel(
      id: 'backup',
      title: 'Backups',
      kind: PanelKind.progress,
      progress: 1,
      value: '100',
      unit: '%',
      subtitle: 'B2 offsite copy OK',
      updatedAt: _now.subtract(const Duration(hours: 6)),
    ),
    HermesMobilePanel(
      id: 'model-router',
      title: 'Model router tiers',
      kind: PanelKind.list,
      items: const [
        PanelItem(label: 'Local model', value: 'off'),
        PanelItem(label: 'OpenRouter flex', value: 'on'),
        PanelItem(label: 'Last canary', value: 'pass'),
      ],
      updatedAt: _now.subtract(const Duration(minutes: 50)),
    ),
    HermesMobilePanel(
      id: 'price-watch',
      title: 'Price watch',
      kind: PanelKind.table,
      columns: const ['Item', 'Now', 'Target'],
      rows: const [
        ['Headphones', '248', '220'],
        ['Stroller', '389', '350'],
      ],
      url: 'https://example.com/watchlist',
      updatedAt: _now.subtract(const Duration(hours: 2)),
    ),
    HermesMobilePanel(
      id: 'brief',
      title: 'Note from the agent',
      kind: PanelKind.text,
      text: 'Nightly backup OK.\n2 PRs waiting on review.',
      updatedAt: _now.subtract(const Duration(hours: 3)),
      source: 'chief',
    ),
  ];

  @override
  PanelsSource get panels => StaticPanelsSource(demoPanels);

  @override
  void dispose() {}
}
