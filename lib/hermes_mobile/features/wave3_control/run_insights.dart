import '../../data/models.dart';

/// What a run did, pulled from its steps: shell commands it ran and files it
/// read or changed. Steps only carry the tool name and its short preview, so
/// this is a best-effort reading of those.
class RunInsights {
  const RunInsights({
    this.commands = const [],
    this.filesChanged = const [],
    this.filesRead = const [],
    this.web = const [],
  });
  final List<String> commands;
  final List<String> filesChanged;
  final List<String> filesRead;
  final List<String> web;

  bool get isEmpty =>
      commands.isEmpty && filesChanged.isEmpty && filesRead.isEmpty && web.isEmpty;

  static const _shellTools = {
    'terminal', 'shell', 'bash', 'exec', 'run command', 'execute code',
    'process', 'command',
  };
  static const _writeTools = {
    'write file', 'patch', 'edit file', 'create file', 'apply patch',
    'str replace', 'replace in file', 'delete file', 'move file',
  };
  static const _readTools = {
    'read file', 'search files', 'list files', 'view file', 'grep', 'glob',
  };
  static const _webTools = {
    'web search', 'web extract', 'browser navigate', 'web fetch', 'fetch url',
    'browse',
  };

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[_\-]+'), ' ').trim();

  static final _pathLike = RegExp(r'(~?/?[\w.\-]+/)*[\w.\-]+\.[A-Za-z0-9]{1,8}');

  static RunInsights from(HermesMobileRun run) => fromSteps(run.steps);

  static RunInsights fromSteps(List<HermesMobileStep> steps) {
    final commands = <String>[];
    final changed = <String>[];
    final read = <String>[];
    final web = <String>[];
    void add(List<String> to, String v) {
      final t = v.trim();
      if (t.isNotEmpty && !to.contains(t)) to.add(t);
    }

    for (final s in steps) {
      final name = _norm(s.label);
      final detail = (s.detail ?? '').trim();
      if (detail.isEmpty) continue;
      if (_shellTools.any(name.contains)) {
        add(commands, detail);
      } else if (_writeTools.any(name.contains)) {
        add(changed, _pathLike.firstMatch(detail)?.group(0) ?? detail);
      } else if (_readTools.any(name.contains)) {
        add(read, _pathLike.firstMatch(detail)?.group(0) ?? detail);
      } else if (_webTools.any(name.contains)) {
        add(web, detail);
      }
    }
    return RunInsights(
      commands: commands,
      filesChanged: changed,
      filesRead: read.where((f) => !changed.contains(f)).toList(),
      web: web,
    );
  }
}

/// How each run control works against the engine in use. Hermes' API server
/// (the transport Petasos uses for chat) can only interrupt a turn: closing the
/// SSE stream stops the agent. Native steer exists on the Desktop gateway
/// WebSocket (`steerPrompt`), which Petasos chats do not ride, and no transport
/// exposes pause. So pause and steer are emulated: interrupt, then send a
/// follow-up turn with the user's guidance in the same session.
enum ControlMode { native, emulated, unavailable }

class RunControlSupport {
  const RunControlSupport({
    this.stop = ControlMode.native,
    this.pause = ControlMode.emulated,
    this.steer = ControlMode.emulated,
    this.takeOver = ControlMode.emulated,
  });
  final ControlMode stop;
  final ControlMode pause;
  final ControlMode steer;
  final ControlMode takeOver;

  static const hermesApiServer = RunControlSupport();

  static String explain(ControlMode m) => switch (m) {
    ControlMode.native => 'Handled by Hermes directly.',
    ControlMode.emulated =>
      'Hermes cannot pause or steer a running turn over this connection, so '
          'Petasos stops the turn and sends your guidance as the next message in '
          'the same chat. Work already done is kept.',
    ControlMode.unavailable => 'Not available on this connection.',
  };
}

/// Prompt for resuming a paused run.
const resumePrompt =
    'Continue the task you were working on from where you stopped. '
    'Do not redo steps that already finished.';

/// Prompt for steering a run with [guidance].
String steerPrompt(String guidance) =>
    'Change of direction for the task you were just doing: ${guidance.trim()}\n'
    'Keep what already finished and continue with this change.';

/// Prompt when the user hands a run back after taking over.
String handBackPrompt(String note) {
  final n = note.trim();
  return n.isEmpty
      ? 'I took over and handled part of this myself. Check the current state '
            'and continue the task from there.'
      : 'I took over and did this myself: $n\nCheck the current state and '
            'continue the task from there.';
}
