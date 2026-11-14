import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'w2_settings.dart';
import 'w2_theme.dart';

/// Appearance, voice and haptics.
class W2AppearanceScreen extends StatelessWidget {
  const W2AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = W2Settings.current;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance and voice')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final c = context.hermesMobile;
          final dynamicAvailable = W2DynamicAccents.cached != null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SectionHeader('Color'),
              ),
              SwitchListTile(
                key: const ValueKey('w2-dynamic-color'),
                title: const Text('Material You colors'),
                subtitle: Text(
                  dynamicAvailable
                      ? 'Follow your wallpaper accent'
                      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                      ? 'Needs Android 12 or newer'
                      : 'Available on Android 12+',
                ),
                value: s.dynamicColor,
                onChanged: (v) => s.setDynamicColor(v),
              ),
              if (!s.dynamicColor || !dynamicAvailable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final (name, argb) in w2AccentPresets)
                        Tooltip(
                          message: name,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              W2Haptics.selection();
                              s.setAccent(argb == 0xFF3E63DD ? null : argb);
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(argb),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: (s.accentArgb ?? 0xFF3E63DD) == argb
                                      ? c.text
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              SwitchListTile(
                key: const ValueKey('w2-amoled'),
                title: const Text('Pure black (AMOLED)'),
                subtitle: const Text('True black background in dark mode'),
                value: s.amoled,
                onChanged: (v) => s.setAmoled(v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SectionHeader('Text'),
              ),
              ListTile(
                title: const Text('Text size'),
                subtitle: Slider(
                  key: const ValueKey('w2-text-size'),
                  value: s.textScale,
                  min: 0.85,
                  max: 1.4,
                  divisions: 11,
                  label: '${(s.textScale * 100).round()}%',
                  onChanged: (v) => s.setTextScale(v),
                ),
                trailing: Text('${(s.textScale * 100).round()}%'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Hermes replies use this size.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SectionHeader('Feel and layout'),
              ),
              SwitchListTile(
                key: const ValueKey('w2-haptics'),
                title: const Text('Haptics'),
                subtitle: const Text('Light taps on send, actions and voice turns'),
                value: s.haptics,
                onChanged: (v) => s.setHaptics(v),
              ),
              SwitchListTile(
                title: const Text('Two panes on large screens'),
                subtitle: const Text('Chats beside the conversation on tablets and foldables'),
                value: s.twoPane,
                onChanged: (v) => s.setTwoPane(v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SectionHeader('Voice'),
              ),
              SwitchListTile(
                key: const ValueKey('w2-auto-read'),
                title: const Text('Read replies aloud'),
                subtitle: const Text('Speak each finished reply'),
                value: s.autoReadAloud,
                onChanged: (v) => s.setAutoReadAloud(v),
              ),
              SwitchListTile(
                title: const Text('Interrupt by talking'),
                subtitle: const Text('In voice mode, speaking stops the reply'),
                value: s.bargeIn,
                onChanged: (v) => s.setBargeIn(v),
              ),
              ListTile(
                title: const Text('Speech rate'),
                subtitle: Slider(
                  value: s.speechRate,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  onChanged: (v) => s.setSpeechRate(v),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
