import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../cards/blocks.dart';
import '../../chat/chat_controller.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/message_views.dart';
import 'w2_api.dart';
import 'w2_branches.dart';
import 'w2_canvas.dart';
import 'w2_settings.dart';
import 'w2_voice.dart';

/// Long-press actions for one message in the thread.
Future<void> showW2MessageActions(
  BuildContext context,
  ChatController ctl,
  int index,
) async {
  if (index < 0 || index >= ctl.messages.length) return;
  final m = ctl.messages[index];
  final settings = W2Settings.current;
  final pinned = settings.isMessagePinned(ctl.chatId, m.text);
  final state = HermesMobileScope.read(context);
  W2Haptics.selection();
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                replyPlainText(m.text).replaceAll(RegExp(r'\s+'), ' ').trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ),
            _row(c, 'copy', Icons.copy_rounded, 'Copy'),
            _row(c, 'share', Icons.ios_share_rounded, 'Share text'),
            _row(c, 'image', Icons.image_outlined, 'Share as image'),
            _row(
              c,
              'pin',
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              pinned ? 'Unpin message' : 'Pin message',
            ),
            if (m.isUser && !ctl.running)
              _row(c, 'edit', Icons.edit_outlined, 'Edit and resend'),
            if (!m.isUser && !ctl.running)
              _row(c, 'regen', Icons.refresh_rounded, 'Regenerate'),
            _row(c, 'fork', Icons.call_split_rounded, 'Fork chat from here'),
            if (!m.isUser) ...[
              _row(c, 'read', Icons.volume_up_outlined, 'Read aloud'),
              _row(c, 'canvas', Icons.edit_note_rounded, 'Open in canvas'),
            ],
            const Divider(height: 16),
            _row(c, 'task', Icons.event_repeat_rounded, 'Turn into task'),
            _row(c, 'reminder', Icons.alarm_add_rounded, 'Turn into reminder'),
            _row(c, 'panel', Icons.dashboard_customize_outlined, 'Turn into Home panel'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'copy':
      await Clipboard.setData(ClipboardData(text: replyPlainText(m.text)));
      if (context.mounted) _snack(context, 'Copied');
    case 'share':
      await SharePlus.instance.share(
        ShareParams(subject: ctl.title, text: replyPlainText(m.text)),
      );
    case 'image':
      await shareMessageAsImage(context, m);
    case 'pin':
      await settings.toggleMessagePin(
        W2PinnedMessage(
          chatId: ctl.chatId,
          chatTitle: ctl.title,
          text: m.text,
          fromUser: m.isUser,
          pinnedAt: DateTime.now(),
        ),
      );
      if (context.mounted) _snack(context, pinned ? 'Unpinned' : 'Pinned');
    case 'edit':
      await showW2EditDialog(context, ctl, index);
    case 'regen':
      await ctl.regenerate(index);
    case 'fork':
      final fork = state.forkChat(ctl, index);
      state.openController(fork);
      if (context.mounted) _snack(context, 'Forked into a new chat');
    case 'read':
      await W2ReadAloud.instance.speak(m.text);
    case 'canvas':
      if (!context.mounted) return;
      final edited = await openW2Canvas(context, W2CanvasDoc.fromMessage(m.text));
      if (edited != null) await ctl.send(edited);
    case 'task':
      if (context.mounted) await showW2TaskSheet(context, m.text);
    case 'reminder':
      if (context.mounted) await showW2ReminderSheet(context, m.text);
    case 'panel':
      if (context.mounted) await turnIntoPanel(context, ctl.title, m.text);
  }
}

Widget _row(BuildContext c, String value, IconData icon, String label) =>
    ListTile(
      dense: true,
      leading: Icon(icon, size: 22),
      title: Text(label),
      onTap: () => Navigator.pop(c, value),
    );

void _snack(BuildContext context, String m) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

/// Edit a sent message: resend here as a new branch, or fork a new chat.
Future<void> showW2EditDialog(
  BuildContext context,
  ChatController ctl,
  int index,
) async {
  final m = ctl.messages[index];
  final text = TextEditingController(text: m.text);
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Edit message'),
      content: TextField(
        controller: text,
        autofocus: true,
        minLines: 2,
        maxLines: 8,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'fork'),
          child: const Text('Fork chat'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'send'),
          child: const Text('Resend'),
        ),
      ],
    ),
  );
  final value = text.text.trim();
  if (choice == null || value.isEmpty || !context.mounted) return;
  if (choice == 'send') {
    W2Haptics.light();
    await ctl.editAndResend(index, value, imageDataUrl: m.imageDataUrls.firstOrNull);
  } else {
    final state = HermesMobileScope.read(context);
    final fork = index == 0
        ? state.newChat()
        : state.forkChat(ctl, index - 1);
    state.openController(fork);
    await fork.send(value, imageDataUrl: m.imageDataUrls.firstOrNull);
  }
}

/// Renders the message as a card and shares it as a PNG.
Future<void> shareMessageAsImage(BuildContext context, HermesMobileMessage m) async {
  final key = GlobalKey();
  final c = context.hermesMobile;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dc) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: Container(
                  color: c.background,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      m.isUser ? UserBubble(message: m) : AgentReply(message: m),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: c.accent),
                          const SizedBox(width: 6),
                          Text(
                            'Hermes',
                            style: Theme.of(dc).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dc, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    _lastCapture = await captureBoundary(key);
                    if (dc.mounted) Navigator.pop(dc, true);
                  },
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final bytes = _lastCapture;
  _lastCapture = null;
  if (bytes == null) return;
  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/hermes-message-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
  } catch (_) {
    if (context.mounted) _snack(context, 'Could not share the image.');
  }
}

Uint8List? _lastCapture;

/// Captures a [RepaintBoundary] by key. Exposed for the share dialog and tests.
Future<Uint8List?> captureBoundary(GlobalKey key, {double pixelRatio = 3}) async {
  final obj = key.currentContext?.findRenderObject();
  if (obj is! RenderRepaintBoundary) return null;
  final image = await obj.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Turn a message into a scheduled Hermes task.
Future<void> showW2TaskSheet(BuildContext context, String text) async {
  final state = HermesMobileScope.read(context);
  final plain = replyPlainText(text).trim();
  final name = TextEditingController(
    text: plain.length > 40 ? '${plain.substring(0, 40)}…' : plain,
  );
  final schedule = TextEditingController(text: '0 9 * * *');
  final prompt = TextEditingController(text: plain);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(c).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Turn into task', style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(
            controller: schedule,
            decoration: const InputDecoration(
              labelText: 'Schedule',
              helperText: 'Cron (0 9 * * *), "every 2h", or "30m" for once',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: prompt,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'What Hermes should do'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Create task'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await state.backend.createCron(
      name: name.text.trim().isEmpty ? 'Task' : name.text.trim(),
      schedule: schedule.text.trim(),
      prompt: prompt.text.trim(),
    );
    if (context.mounted) _snack(context, 'Task created');
  } catch (e) {
    if (context.mounted) _snack(context, 'Could not create the task. $e');
  }
}

/// One-shot reminder schedules Hermes cron understands.
List<(String, String)> w2ReminderChoices(DateTime now) {
  final tomorrow9 = DateTime(now.year, now.month, now.day + 1, 9);
  final tonight8 = DateTime(now.year, now.month, now.day, 20);
  return [
    ('In 30 minutes', '30m'),
    ('In 1 hour', '1h'),
    ('In 3 hours', '3h'),
    if (now.isBefore(tonight8)) ('Tonight at 8 pm', _iso(tonight8)),
    ('Tomorrow at 9 am', _iso(tomorrow9)),
  ];
}

String _iso(DateTime t) => t.toIso8601String().split('.').first;

Future<void> showW2ReminderSheet(BuildContext context, String text) async {
  final state = HermesMobileScope.read(context);
  final plain = replyPlainText(text).replaceAll(RegExp(r'\s+'), ' ').trim();
  final about = plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
  final picked = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Remind me', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(about, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          for (final (label, schedule) in w2ReminderChoices(DateTime.now()))
            ListTile(
              leading: const Icon(Icons.alarm_rounded),
              title: Text(label),
              onTap: () => Navigator.pop(c, schedule),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null) return;
  try {
    await state.backend.createCron(
      name: 'Reminder: ${about.length > 32 ? '${about.substring(0, 32)}…' : about}',
      schedule: picked,
      prompt: 'Send me this reminder, short and friendly: $about',
    );
    if (context.mounted) _snack(context, 'Reminder set');
  } catch (e) {
    if (context.mounted) _snack(context, 'Could not set the reminder. $e');
  }
}

/// Publishes the message as a Home panel through the Petasos plugin.
Future<void> turnIntoPanel(BuildContext context, String title, String text) async {
  final api = HermesMobileScope.read(context).backend.wave2;
  try {
    final ok = await api.createPanel(title: title, text: replyPlainText(text));
    if (!context.mounted) return;
    if (ok) {
      _snack(context, 'Added to Home panels');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Panels need the Petasos plugin'),
        content: const Text(
          'Install the Petasos plugin on your Hermes host to publish panels from '
          'chat: copy server/hermes_mobile_plugin from the app repo to '
          '~/.hermes/plugins/hermes_mobile, then restart the dashboard. The dashboard '
          'URL must be set under Profile → Connection.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) _snack(context, 'Could not add the panel. $e');
  }
}
