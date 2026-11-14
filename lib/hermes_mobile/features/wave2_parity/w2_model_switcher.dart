import 'package:flutter/material.dart';

import '../../chat/chat_controller.dart';
import '../../data/app_state.dart';
import '../../hermes_mobile_app.dart';
import '../../theme/hermes_mobile_theme.dart';
import 'w2_api.dart';
import 'w2_settings.dart';

final Expando<W2ModelState> _modelCache = Expando('w2model');

/// Small chip above the composer: current model and effort. Tap to switch.
class W2ModelChip extends StatefulWidget {
  const W2ModelChip({super.key, required this.chat});
  final ChatController chat;

  @override
  State<W2ModelChip> createState() => _W2ModelChipState();
}

class _W2ModelChipState extends State<W2ModelChip> {
  W2ModelState? _state;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _state = _modelCache[widget.chat];
    if (_state == null) _load();
  }

  Future<void> _load() async {
    try {
      final api = HermesMobileScope.read(context).backend.wave2;
      final s = await api.modelState(widget.chat.chatId, isDraft: widget.chat.isNew);
      _modelCache[widget.chat] = s;
      if (mounted) setState(() => _state = s);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final s = _state;
    if (_failed) return const SizedBox.shrink();
    final label = s?.current?.model ?? 'Model';
    final effort = s == null || s.effort == 'default' ? '' : ' · ${s.effort}';
    return ActionChip(
      key: const ValueKey('w2-model-chip'),
      visualDensity: VisualDensity.compact,
      avatar: Icon(Icons.auto_awesome_rounded, size: 16, color: c.accent),
      label: Text('$label$effort', overflow: TextOverflow.ellipsis),
      side: BorderSide(color: c.hairline),
      backgroundColor: c.surface,
      onPressed: () async {
        final changed = await showW2ModelSwitcher(context, widget.chat);
        if (changed != null && mounted) setState(() => _state = changed);
      },
    );
  }
}

/// Profile, model and reasoning effort for one chat. Returns the new state.
Future<W2ModelState?> showW2ModelSwitcher(
  BuildContext context,
  ChatController chat,
) async {
  final state = HermesMobileScope.read(context);
  final api = state.backend.wave2;
  W2Haptics.selection();
  final result = await showModalBottomSheet<W2ModelState>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SwitcherSheet(
      api: api,
      chat: chat,
      demo: state.backend.isDemo,
      root: _maybeRoot(context),
    ),
  );
  if (result != null) _modelCache[chat] = result;
  return result;
}

HermesMobileRootController? _maybeRoot(BuildContext context) {
  try {
    return HermesMobileRoot.of(context);
  } catch (_) {
    return null;
  }
}

class _SwitcherSheet extends StatefulWidget {
  const _SwitcherSheet({
    required this.api,
    required this.chat,
    required this.demo,
    this.root,
  });
  final Wave2Api api;
  final ChatController chat;
  final bool demo;
  final HermesMobileRootController? root;

  @override
  State<_SwitcherSheet> createState() => _SwitcherSheetState();
}

class _SwitcherSheetState extends State<_SwitcherSheet> {
  W2ModelState? _state;
  List<W2Profile> _profiles = const [];
  W2ModelChoice? _choice;
  String _effort = 'default';
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.modelState(
        widget.chat.chatId,
        isDraft: widget.chat.isNew,
      );
      final profiles = widget.demo ? await widget.api.profiles() : _liveProfiles();
      if (!mounted) return;
      setState(() {
        _state = s;
        _choice = s.current;
        _effort = s.effort;
        _profiles = profiles;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load models. $e');
    }
  }

  List<W2Profile> _liveProfiles() {
    final root = widget.root;
    if (root == null) return const [];
    final active = root.activeConnection?.id;
    return [
      for (final c in root.savedConnections)
        W2Profile(
          id: c.id,
          label: c.label,
          detail: c.gatewayProfile?.isNotEmpty == true
              ? 'profile ${c.gatewayProfile}'
              : c.baseUrl,
          active: c.id == active,
        ),
    ];
  }

  Future<void> _switchProfile(W2Profile p) async {
    if (p.active) return;
    W2Haptics.selection();
    if (widget.demo) {
      await widget.api.switchProfile(p.id);
      final profiles = await widget.api.profiles();
      if (mounted) setState(() => _profiles = profiles);
      return;
    }
    Navigator.of(context).pop();
    await widget.root?.useConnection(p.id);
  }

  Future<void> _save() async {
    final choice = _choice;
    if (choice == null) return;
    setState(() => _saving = true);
    try {
      await widget.api.setModel(
        widget.chat.chatId,
        choice,
        _effort,
        isDraft: widget.chat.isNew,
      );
      W2Haptics.light();
      if (!mounted) return;
      Navigator.of(context).pop(
        W2ModelState(
          choices: _state!.choices,
          current: choice,
          effort: _effort,
          effortOnServer: _state!.effortOnServer,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not switch the model. $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final s = _state;
    final byProvider = <String, List<W2ModelChoice>>{};
    for (final m in s?.choices ?? const <W2ModelChoice>[]) {
      byProvider.putIfAbsent(m.provider, () => []).add(m);
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Model and profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: c.danger)),
            ),
          if (s == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_profiles.length > 1) ...[
            Text('Profile', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _profiles)
                  ChoiceChip(
                    label: Text(p.label),
                    tooltip: p.detail,
                    selected: p.active,
                    onSelected: (_) => _switchProfile(p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (s != null) ...[
            Text('Reasoning effort', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in w2ReasoningEfforts)
                  ChoiceChip(
                    label: Text(e),
                    selected: _effort == e,
                    onSelected: (_) => setState(() => _effort = e),
                  ),
              ],
            ),
            if (!s.effortOnServer)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'This connection applies effort only through the Desktop '
                  'gateway; the choice is kept for this chat on the phone.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            for (final entry in byProvider.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(entry.key, style: Theme.of(context).textTheme.labelSmall),
              ),
              for (final m in entry.value)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    m == _choice ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: m == _choice ? c.accent : c.textTertiary,
                    size: 20,
                  ),
                  title: Text(m.model),
                  subtitle: m.note == null ? null : Text(m.note!),
                  onTap: () => setState(() => _choice = m),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _choice == null || _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Use for this chat'),
            ),
          ],
        ],
      ),
    );
  }
}
