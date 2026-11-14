import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/common.dart';
import 'w1_controller.dart';
import 'w1_notifications.dart';
import 'w1_widgets_bridge.dart';
import '../wave2_parity/w2_settings.dart';

/// Quiet hours, per-source mute, and a test notification.
class Wave1NotificationSettings extends StatelessWidget {
  const Wave1NotificationSettings({super.key, required this.controller});
  final ProactiveController controller;

  String _hour(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<int?> _pickHour(BuildContext context, int current) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current, minute: 0),
    );
    return t?.hour;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = controller.policy;
        final sources = <String>{
          'approvals',
          'cron',
          'reminders',
          for (final c in controller.cards) c.source.toLowerCase(),
          for (final c in controller.briefs) c.source.toLowerCase(),
          ...p.muted,
        }.toList()..sort();
        return Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: ListView(
            children: [
              SwitchListTile(
                title: const Text('Proactive notifications'),
                subtitle: const Text(
                  'Approvals, briefs and cards from Hermes while the app is '
                  'in the background',
                ),
                value: p.enabled,
                onChanged: (v) => controller.setPolicy(p.copyWith(enabled: v)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SectionHeader('Quiet hours'),
              ),
              SwitchListTile(
                title: const Text('Hold notifications overnight'),
                subtitle: Text(
                  '${_hour(p.quietStart)} to ${_hour(p.quietEnd)}. '
                  'Approvals still arrive, silently.',
                ),
                value: p.quietEnabled,
                onChanged: (v) =>
                    controller.setPolicy(p.copyWith(quietEnabled: v)),
              ),
              ListTile(
                enabled: p.quietEnabled,
                title: const Text('Starts'),
                trailing: Text(_hour(p.quietStart)),
                onTap: () async {
                  final h = await _pickHour(context, p.quietStart);
                  if (h != null) {
                    await controller.setPolicy(p.copyWith(quietStart: h));
                  }
                },
              ),
              ListTile(
                enabled: p.quietEnabled,
                title: const Text('Ends'),
                trailing: Text(_hour(p.quietEnd)),
                onTap: () async {
                  final h = await _pickHour(context, p.quietEnd);
                  if (h != null) {
                    await controller.setPolicy(p.copyWith(quietEnd: h));
                  }
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SectionHeader('Sources'),
              ),
              for (final s in sources)
                SwitchListTile(
                  title: Text(s[0].toUpperCase() + s.substring(1)),
                  value: !p.muted.contains(s),
                  onChanged: (on) {
                    W2Haptics.selection();
                    final muted = {...p.muted};
                    on ? muted.remove(s) : muted.add(s);
                    controller.setPolicy(p.copyWith(muted: muted));
                  },
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SectionHeader('Home-screen panel widget'),
              ),
              _PinnedPanelPicker(controller: controller),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Send a test notification'),
                  onPressed: () async {
                    await Wave1Notifier.shared.showTest();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sent. Check your notification shade.'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Chooses which Home panel the "Hermes panel" widget shows.
class _PinnedPanelPicker extends StatefulWidget {
  const _PinnedPanelPicker({required this.controller});
  final ProactiveController controller;

  @override
  State<_PinnedPanelPicker> createState() => _PinnedPanelPickerState();
}

class _PinnedPanelPickerState extends State<_PinnedPanelPicker> {
  String? _pinned;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() => _pinned = p.getString(HermesMobileWidgetBridge.pinnedPanelKey));
      }
    });
  }

  Future<void> _pin(String id) async {
    setState(() => _pinned = id);
    final p = await SharedPreferences.getInstance();
    await p.setString(HermesMobileWidgetBridge.pinnedPanelKey, id);
    widget.controller.touch();
  }

  @override
  Widget build(BuildContext context) {
    final panels = widget.controller.state.panels?.panels ?? const [];
    if (panels.isEmpty) {
      return const ListTile(
        dense: true,
        title: Text('No panels yet'),
        subtitle: Text('Panels from Home appear here once they load.'),
      );
    }
    return RadioGroup<String>(
      groupValue: _pinned ?? panels.first.id,
      onChanged: (v) {
        if (v != null) _pin(v);
      },
      child: Column(
        children: [
          for (final panel in panels)
            RadioListTile<String>(
              value: panel.id,
              title: Text(panel.title),
              subtitle: panel.subtitle == null ? null : Text(panel.subtitle!),
            ),
        ],
      ),
    );
  }
}
