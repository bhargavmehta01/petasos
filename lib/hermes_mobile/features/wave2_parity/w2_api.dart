import 'dart:async';

import '../../../core/services/chat_model_override_store.dart';
import '../../../core/services/connection_manager.dart';
import '../../../core/services/desktop_gateway_client.dart';
import '../../data/backend.dart';
import '../../data/live_backend.dart';
import '../../data/models.dart';
import 'w2_settings.dart';

/// One selectable model from the active profile's catalog.
class W2ModelChoice {
  const W2ModelChoice({required this.provider, required this.model, this.note});
  final String provider;
  final String model;
  final String? note;

  String get label => model;
  @override
  bool operator ==(Object other) =>
      other is W2ModelChoice &&
      other.provider == provider &&
      other.model == model;
  @override
  int get hashCode => Object.hash(provider, model);
}

/// What the model switcher needs for one chat.
class W2ModelState {
  const W2ModelState({
    required this.choices,
    this.current,
    this.effort = 'default',
    this.effortOnServer = false,
  });
  final List<W2ModelChoice> choices;
  final W2ModelChoice? current;
  final String effort;

  /// True when the host applies reasoning effort (Desktop gateway); otherwise
  /// the choice is kept on the phone and sent as a hint.
  final bool effortOnServer;
}

const w2ReasoningEfforts = <String>[
  'default',
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
];

/// A Hermes profile (demo) or a saved connection (live) the user can switch to.
class W2Profile {
  const W2Profile({
    required this.id,
    required this.label,
    this.detail = '',
    this.active = false,
  });
  final String id;
  final String label;
  final String detail;
  final bool active;
}

class W2ProjectFile {
  const W2ProjectFile({required this.name, required this.path, this.size});
  final String name;
  final String path;
  final int? size;
}

class W2ProjectDetails {
  const W2ProjectDetails({
    required this.instructions,
    this.files = const [],
    this.serverBacked = false,
  });
  final String instructions;
  final List<W2ProjectFile> files;

  /// False when the Petasos plugin is missing: instructions stay on the phone and
  /// are sent with the first message of each new project chat.
  final bool serverBacked;
}

/// A slash command offered in the composer.
class W2SlashCommand {
  const W2SlashCommand(this.name, this.description, {this.args = ''});
  final String name;
  final String description;
  final String args;
}

/// Hermes CLI/gateway slash commands the API server understands, plus the
/// phone-side ones handled before sending.
const w2SlashCommands = <W2SlashCommand>[
  W2SlashCommand('new', 'Start a fresh chat'),
  W2SlashCommand('model', 'Switch model and reasoning effort'),
  W2SlashCommand('voice', 'Open voice mode'),
  W2SlashCommand('canvas', 'Open an empty canvas'),
  W2SlashCommand('search', 'Search chats, cards, memory and skills'),
  W2SlashCommand('retry', 'Regenerate the last reply'),
  W2SlashCommand('undo', 'Remove the last exchange'),
  W2SlashCommand('remind', 'Create a reminder', args: '<when> <what>'),
  W2SlashCommand('compress', 'Compress the conversation context'),
  W2SlashCommand('usage', 'Show token usage for this chat'),
  W2SlashCommand('skills', 'List installed skills'),
  W2SlashCommand('personality', 'Set the agent personality', args: '<name>'),
];

/// Commands the phone handles itself instead of sending to Hermes.
const w2LocalSlash = {'new', 'model', 'voice', 'canvas', 'search', 'retry', 'undo', 'remind'};

/// Wave 2 data that the base [HermesMobileBackend] does not cover. Get it with
/// `backend.wave2`.
abstract class Wave2Api {
  Future<W2ModelState> modelState(String chatId, {bool isDraft = false});
  Future<void> setModel(
    String chatId,
    W2ModelChoice choice,
    String effort, {
    bool isDraft = false,
  });

  /// Demo profiles. Live connections list saved connections instead.
  Future<List<W2Profile>> profiles();
  Future<void> switchProfile(String id);

  /// Whether the Petasos server plugin answers on this host.
  Future<bool> pluginAvailable();

  Future<W2ProjectDetails> projectDetails(HermesMobileProject project);
  Future<void> saveProjectInstructions(String projectId, String text);

  /// Publishes a Home panel from a message. False when the plugin is missing.
  Future<bool> createPanel({required String title, required String text});
}

/// True when the plugin's /health lists the Wave 2 routes.
bool w2PluginHasWave2(Map<String, dynamic> health) {
  final features = health['features'];
  return health['plugin'] == 'hermes_mobile' &&
      features is List &&
      features.contains('w2.projects');
}

final Expando<Wave2Api> _apis = Expando('wave2api');

extension Wave2BackendX on HermesMobileBackend {
  Wave2Api get wave2 => _apis[this] ??= switch (this) {
    final LiveBackend live => LiveWave2Api(live),
    _ => DemoWave2Api(),
  };
}

/// Sample data for demo mode and tests.
class DemoWave2Api implements Wave2Api {
  static const demoChoices = [
    W2ModelChoice(provider: 'deepseek', model: 'deepseek-v4-flash', note: 'Fast, cheap'),
    W2ModelChoice(provider: 'anthropic', model: 'claude-sonnet-4.5', note: 'Best for code'),
    W2ModelChoice(provider: 'openai', model: 'gpt-5-mini', note: 'Balanced'),
    W2ModelChoice(provider: 'openrouter', model: 'qwen3-coder', note: 'Open model'),
  ];
  final Map<String, W2ModelChoice> _models = {};
  final Map<String, String> _effort = {};
  String _profile = 'default';
  final Map<String, String> _instructions = {
    'p-hermes_mobile': 'Flutter 3.44, Inter font, keep upstream engine untouched. '
        'Small fenced edits only.',
  };
  final List<Map<String, String>> panels = [];

  @override
  Future<W2ModelState> modelState(String chatId, {bool isDraft = false}) async =>
      W2ModelState(
        choices: demoChoices,
        current: _models[chatId] ?? demoChoices.first,
        effort: _effort[chatId] ?? 'default',
        effortOnServer: true,
      );

  @override
  Future<void> setModel(
    String chatId,
    W2ModelChoice choice,
    String effort, {
    bool isDraft = false,
  }) async {
    _models[chatId] = choice;
    _effort[chatId] = effort;
  }

  @override
  Future<List<W2Profile>> profiles() async => [
    W2Profile(id: 'default', label: 'Default', detail: 'Personal agent', active: _profile == 'default'),
    W2Profile(id: 'coder', label: 'Coder', detail: 'Repos and CI', active: _profile == 'coder'),
    W2Profile(id: 'family', label: 'Family', detail: 'Calendar, shopping', active: _profile == 'family'),
  ];

  @override
  Future<void> switchProfile(String id) async => _profile = id;

  @override
  Future<bool> pluginAvailable() async => true;

  @override
  Future<W2ProjectDetails> projectDetails(HermesMobileProject project) async =>
      W2ProjectDetails(
        instructions: _instructions[project.id] ?? '',
        serverBacked: true,
        files: project.id == 'p-hermes_mobile'
            ? const [
                W2ProjectFile(name: 'WAVES.md', path: 'work/WAVES.md', size: 5828),
                W2ProjectFile(name: 'pubspec.yaml', path: 'pubspec.yaml', size: 2410),
                W2ProjectFile(name: 'hermes_mobile_theme.dart', path: 'lib/hermes_mobile/theme/hermes_mobile_theme.dart', size: 9800),
              ]
            : const [
                W2ProjectFile(name: 'selfheal.sh', path: 'scripts/selfheal.sh', size: 3120),
                W2ProjectFile(name: 'docker-compose.yml', path: 'docker-compose.yml', size: 1840),
              ],
      );

  @override
  Future<void> saveProjectInstructions(String projectId, String text) async =>
      _instructions[projectId] = text;

  @override
  Future<bool> createPanel({required String title, required String text}) async {
    panels.add({'title': title, 'text': text});
    return true;
  }
}

/// Live Wave 2 data over the engine clients and the optional Petasos plugin.
class LiveWave2Api implements Wave2Api {
  LiveWave2Api(this.backend)
    : _api = ApiClient(
        baseUrl: backend.conn.baseUrl,
        apiKey: backend.conn.apiKey,
        pathPrefix: backend.conn.gatewayPrefix ?? '',
        gatewayProfile: backend.conn.gatewayProfile,
        clientCertificate: backend.conn.clientCertificate,
      );

  final LiveBackend backend;
  final ApiClient _api;
  DashboardClient? _dash;
  bool? _plugin;

  SavedConnection get conn => backend.conn;
  DashboardClient get _dashboard =>
      _dash ??= DashboardClient.fromConnection(conn);
  bool get _hasDesktop => (conn.desktopGatewayUrl?.trim() ?? '').isNotEmpty;

  static List<W2ModelChoice> parseChoices(Map<String, dynamic> options) {
    final providers = options['providers'];
    if (providers is! List) return const [];
    final out = <W2ModelChoice>[];
    for (final p in providers) {
      if (p is! Map) continue;
      final provider = (p['slug'] ?? p['id'])?.toString().trim() ?? '';
      final models = p['models'];
      if (provider.isEmpty || models is! List) continue;
      for (final m in models) {
        final id = m is String
            ? m.trim()
            : m is Map
            ? ((m['id'] ?? m['model'] ?? m['name'])?.toString().trim() ?? '')
            : '';
        if (id.isNotEmpty) out.add(W2ModelChoice(provider: provider, model: id));
      }
    }
    return out;
  }

  @override
  Future<W2ModelState> modelState(String chatId, {bool isDraft = false}) async {
    final options = await _api.getModelOptions();
    final choices = parseChoices(options);
    final store = ChatModelOverrideStore(backend.prefs);
    final saved = store.read(connectionIdentity: conn.id, sessionId: chatId);
    String? model = saved?.model;
    String? provider = saved?.provider;
    if (model == null && !isDraft) {
      try {
        final s = await _api.getSession(chatId);
        model = s['model']?.toString();
      } catch (_) {}
    }
    model ??= options['model']?.toString();
    provider ??= options['provider']?.toString();
    final current =
        choices.where((c) => c.model == model && c.provider == provider).firstOrNull ??
        choices.where((c) => c.model == model).firstOrNull;
    return W2ModelState(
      choices: choices,
      current: current,
      effort: saved?.reasoningEffort ??
          W2Settings.current.reasoningEffort(chatId) ??
          'default',
      effortOnServer: _hasDesktop,
    );
  }

  @override
  Future<void> setModel(
    String chatId,
    W2ModelChoice choice,
    String effort, {
    bool isDraft = false,
  }) async {
    if (_hasDesktop) {
      final gw = DesktopGatewayClient.fromConnection(conn);
      try {
        await gw.setSessionModel(
          sessionId: chatId,
          provider: choice.provider,
          model: choice.model,
        );
        if (effort != 'default') {
          await gw.setSessionReasoning(sessionId: chatId, effort: effort);
        }
      } finally {
        gw.close();
      }
    } else {
      await _api.setSessionModel(
        sessionId: chatId,
        provider: choice.provider,
        model: choice.model,
        createSessionIfMissing: isDraft,
      );
    }
    await ChatModelOverrideStore(backend.prefs).save(
      connectionIdentity: conn.id,
      sessionId: chatId,
      provider: choice.provider,
      model: choice.model,
      reasoningEffort: effort == 'default' ? null : effort,
    );
    await W2Settings.current.setReasoningEffort(
      chatId,
      effort == 'default' ? null : effort,
    );
  }

  @override
  Future<List<W2Profile>> profiles() async => const [];

  @override
  Future<void> switchProfile(String id) async {}

  @override
  Future<bool> pluginAvailable() async {
    if (_plugin != null) return _plugin!;
    try {
      final r = await _dashboard.apiGet('plugins/hermes_mobile/health');
      return _plugin = w2PluginHasWave2(r);
    } catch (_) {
      return _plugin = false;
    }
  }

  @override
  Future<W2ProjectDetails> projectDetails(HermesMobileProject project) async {
    final local = W2Settings.current.projectInstructions(project.id);
    if (!await pluginAvailable()) {
      return W2ProjectDetails(instructions: local);
    }
    try {
      final id = Uri.encodeComponent(project.id);
      final r = await _dashboard.apiGet(
        'plugins/hermes_mobile/w2/projects/$id',
        queryParameters: {if (project.path != null) 'path': project.path!},
      );
      final files = <W2ProjectFile>[
        for (final f in (r['files'] as List? ?? const []))
          if (f is Map)
            W2ProjectFile(
              name: '${f['name'] ?? ''}',
              path: '${f['path'] ?? f['name'] ?? ''}',
              size: (f['size'] as num?)?.toInt(),
            ),
      ];
      final remote = (r['instructions'] ?? '').toString();
      return W2ProjectDetails(
        instructions: remote.isEmpty ? local : remote,
        files: files,
        serverBacked: true,
      );
    } catch (_) {
      return W2ProjectDetails(instructions: local);
    }
  }

  @override
  Future<void> saveProjectInstructions(String projectId, String text) async {
    await W2Settings.current.setProjectInstructions(projectId, text);
    if (await pluginAvailable()) {
      final id = Uri.encodeComponent(projectId);
      await _dashboard.apiPut(
        'plugins/hermes_mobile/w2/projects/$id/instructions',
        body: {'instructions': text},
      );
    }
  }

  @override
  Future<bool> createPanel({required String title, required String text}) async {
    if (!await pluginAvailable()) return false;
    await _dashboard.apiPost(
      'plugins/hermes_mobile/w2/panels',
      body: {'title': title, 'kind': 'text', 'text': text},
    );
    return true;
  }
}
