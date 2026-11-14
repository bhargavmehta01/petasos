import 'package:flutter/material.dart';

import '../../../cards/card_widgets.dart';
import '../../../data/app_state.dart';
import '../../../theme/hermes_mobile_theme.dart';
import '../../../widgets/common.dart';
import '../w4_api.dart';
import '../w4_controller.dart';
import '../w4_models.dart';
import 'w4_commitments.dart';
import 'w4_recap.dart';
import 'w4_watchers.dart';
import 'w4_widgets.dart';
import '../../wave2_parity/w2_settings.dart';

/// The Profile entry for Wave 4: one group, dropped into Settings with a
/// single fenced line.
class Wave4SettingsGroup extends StatelessWidget {
  const Wave4SettingsGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final w4 = HermesMobileScope.of(context).wave4;
    void push(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget row(
      IconData icon,
      String title,
      Widget screen, {
      String? trailing,
    }) => ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing, style: Theme.of(context).textTheme.bodySmall),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () => push(screen),
    );
    return ListenableBuilder(
      listenable: w4,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Autopilot'),
          HermesMobileCardFrame(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                row(
                  Icons.tune_rounded,
                  'Proactivity',
                  const AutopilotSettingsScreen(),
                  trailing: w4.level.label,
                ),
                Divider(height: 1, indent: 52, color: c.hairline),
                row(
                  Icons.visibility_outlined,
                  'Watchers',
                  const WatchersScreen(),
                  trailing: w4.watchers.isEmpty
                      ? null
                      : '${w4.watchers.length}',
                ),
                Divider(height: 1, indent: 52, color: c.hairline),
                row(
                  Icons.handshake_outlined,
                  'Commitments',
                  const CommitmentsScreen(),
                ),
                Divider(height: 1, indent: 52, color: c.hairline),
                row(
                  Icons.history_rounded,
                  'Autopilot log',
                  const RecapScreen(),
                ),
                Divider(height: 1, indent: 52, color: c.hairline),
                row(
                  Icons.sensors_rounded,
                  'Context triggers',
                  const ContextTriggersScreen(),
                  trailing: '${w4.triggers.where((t) => t.enabled).length} on',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Proactivity dial, undo window, offline queue and plugin status.
class AutopilotSettingsScreen extends StatelessWidget {
  const AutopilotSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    final w4 = state.wave4;
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Proactivity')),
      body: ListenableBuilder(
        listenable: w4,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SectionHeader('How often Hermes reaches out'),
            HermesMobileCardFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<ProactivityLevel>(
                    showSelectedIcon: false,
                    segments: [
                      for (final l in ProactivityLevel.values)
                        ButtonSegment(value: l, label: Text(l.label)),
                    ],
                    selected: {w4.level},
                    onSelectionChanged: (s) async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      final ok = await w4.setLevel(s.first);
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Saved as a standing rule on Hermes.'
                                : 'Saved on this phone.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(w4.level.blurb, style: t.bodyMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        w4.levelSynced
                            ? Icons.cloud_done_outlined
                            : Icons.phone_android_rounded,
                        size: 16,
                        color: w4.levelSynced ? c.success : c.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          w4.levelSynced
                              ? 'Hermes has this as a standing rule.'
                              : 'Only on this phone so far.',
                          style: t.bodySmall,
                        ),
                      ),
                      if (!w4.levelSynced && !state.backend.isDemo)
                        TextButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.maybeOf(
                              context,
                            );
                            await w4.saveLevelViaChat();
                            messenger?.showSnackBar(
                              SnackBar(
                                content: Text(
                                  w4.levelSynced
                                      ? 'Asked Hermes to remember it.'
                                      : 'Could not reach Hermes.',
                                ),
                              ),
                            );
                          },
                          child: const Text('Tell Hermes'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SectionHeader('Undo window'),
            HermesMobileCardFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Approvals and card buttons that send something wait this '
                    'long, with an Undo, before they go out.',
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in const [0, 5, 10, 30])
                        ChoiceChip(
                          label: Text(s == 0 ? 'Off' : '${s}s'),
                          selected: w4.undoWindow.inSeconds == s,
                          onSelected: (_) =>
                              w4.setUndoWindow(Duration(seconds: s)),
                        ),
                    ],
                  ),
                  if (state.backend.isDemo) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        final api = w4.api;
                        if (api is DemoWave4Api) {
                          api.simulateOutbound(
                            'Email to the landlord: "Rent sent for November"',
                          );
                          w4.refreshHeld();
                        }
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Held on Home for 10 seconds. Undo it there.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.outbox_outlined, size: 18),
                      label: const Text('Try it: agent sends an email'),
                    ),
                  ],
                ],
              ),
            ),
            const SectionHeader('Offline'),
            HermesMobileCardFrame(
              child: Row(
                children: [
                  Icon(
                    w4.online
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: w4.online ? c.success : c.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      w4.queue.isEmpty
                          ? 'Messages typed while Hermes is unreachable wait '
                                'here and send when it is back.'
                          : '${w4.queue.length} queued. Checking every 15 seconds.',
                      style: t.bodyMedium,
                    ),
                  ),
                  if (w4.queue.isNotEmpty)
                    TextButton(
                      onPressed: w4.checkOnline,
                      child: const Text('Send now'),
                    ),
                ],
              ),
            ),
            const SectionHeader('Server plugin'),
            HermesMobileCardFrame(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    w4.pluginAvailable
                        ? Icons.extension_rounded
                        : Icons.extension_off_outlined,
                    color: w4.pluginAvailable ? c.success : c.textTertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      w4.pluginAvailable
                          ? 'Petasos plugin found. Watchers keep history, the '
                                'recap can revert, and the dial is a standing rule.'
                          : 'Petasos plugin not found. Watchers fall back to '
                                'scheduled tasks and the recap shows cron runs only. '
                                'Install server/hermes_mobile_plugin into ~/.hermes/plugins/hermes_mobile '
                                'and restart the dashboard.',
                      style: t.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opt-in on-device triggers. Off by default; each asks for its own
/// permission when turned on.
class ContextTriggersScreen extends StatelessWidget {
  const ContextTriggersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w4 = HermesMobileScope.of(context).wave4;
    return Scaffold(
      appBar: AppBar(title: const Text('Context triggers')),
      body: ListenableBuilder(
        listenable: w4,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Let moments on this phone start a Hermes run. Everything is off '
              'until you turn it on, and signals stay on the phone: only the '
              'prompt is sent.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final t in w4.triggers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TriggerCard(trigger: t, w4: w4),
              ),
          ],
        ),
      ),
    );
  }
}

class _TriggerCard extends StatelessWidget {
  const _TriggerCard({required this.trigger, required this.w4});
  final ContextTrigger trigger;
  final Wave4Controller w4;

  IconData get _icon => switch (trigger.kind) {
    ContextTriggerKind.arriveHome => Icons.home_outlined,
    ContextTriggerKind.carBluetooth => Icons.directions_car_outlined,
    ContextTriggerKind.chargingAtNight => Icons.battery_charging_full_rounded,
    ContextTriggerKind.calendarEnd => Icons.event_available_outlined,
  };

  String? get _paramLabel => switch (trigger.kind) {
    ContextTriggerKind.carBluetooth =>
      'Car Bluetooth name (blank = any car kit)',
    ContextTriggerKind.arriveHome => 'Home as "lat,lng" (radius 150 m)',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = trigger;
    final isDemo = HermesMobileScope.of(context).backend.isDemo;
    return HermesMobileCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _icon,
                size: 20,
                color: t.enabled ? c.accent : c.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.kind.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: t.enabled,
                onChanged: (on) async {
                  W2Haptics.selection();
                  if (on && !isDemo) {
                    final granted = await w4.requestPermission(t.kind);
                    if (!granted && context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Turned on. Android has not granted the permission '
                            'yet, so this fires only while Hermes is open.',
                          ),
                        ),
                      );
                    }
                  }
                  await w4.updateTrigger(t.copyWith(enabled: on));
                },
              ),
            ],
          ),
          Text(t.kind.explain, style: Theme.of(context).textTheme.bodySmall),
          if (t.enabled) ...[
            const SizedBox(height: 8),
            Text(
              '"${t.effectivePrompt}"',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _edit(context),
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final id = await w4.onSignal(t.kind, force: true);
                    messenger?.showSnackBar(
                      SnackBar(
                        content: Text(
                          id == null
                              ? 'Did not run'
                              : 'Started "${t.kind.label}" in a new chat',
                        ),
                      ),
                    );
                  },
                  child: const Text('Test now'),
                ),
                if (t.lastFired != null)
                  W4Pill(label: 'Last ran ${relativeTime(t.lastFired)} ago'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final prompt = TextEditingController(text: trigger.effectivePrompt);
    final param = TextEditingController(text: trigger.param ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(trigger.kind.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: prompt,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Prompt'),
            ),
            if (_paramLabel != null)
              TextField(
                controller: param,
                decoration: InputDecoration(labelText: _paramLabel),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save != true) return;
    await w4.updateTrigger(
      trigger.copyWith(prompt: prompt.text.trim(), param: param.text.trim()),
    );
  }
}
