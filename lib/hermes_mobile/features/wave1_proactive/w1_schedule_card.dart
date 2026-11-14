import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_controller.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import 'w1_schedule.dart';

/// What the user chose on the schedule preview.
enum SchedulePreviewChoice { created, sendAsMessage }

/// Preview card for a detected schedule: what runs, when, and the cron
/// expression. Confirm creates the Hermes cron job.
class SchedulePreviewCard extends StatefulWidget {
  const SchedulePreviewCard({
    super.key,
    required this.intent,
    required this.onConfirm,
    required this.onSendAsMessage,
    required this.onCancel,
  });
  final ScheduleIntent intent;
  final Future<void> Function(ScheduleIntent intent) onConfirm;
  final VoidCallback onSendAsMessage;
  final VoidCallback onCancel;

  @override
  State<SchedulePreviewCard> createState() => _SchedulePreviewCardState();
}

class _SchedulePreviewCardState extends State<SchedulePreviewCard> {
  late final _name = TextEditingController(text: widget.intent.name);
  late final _prompt = TextEditingController(text: widget.intent.prompt);
  late final _schedule = TextEditingController(text: widget.intent.schedule);
  bool _editing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _schedule.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(
        widget.intent.copyWith(
          name: _name.text.trim().isEmpty ? null : _name.text.trim(),
          prompt: _prompt.text.trim().isEmpty ? null : _prompt.text.trim(),
          schedule: _schedule.text.trim().isEmpty ? null : _schedule.text.trim(),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create it: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final i = widget.intent;
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 13, color: c.text);
    return Container(
      key: const ValueKey('schedule-preview'),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(HermesMobileRadius.card),
        border: Border.all(color: c.accent.withValues(alpha: 0.4)),
        boxShadow: hermesMobileShadow(context),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat_rounded, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i.oneShot ? 'Schedule this once?' : 'Set up a scheduled task?',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: _editing ? 'Done editing' : 'Edit',
                visualDensity: VisualDensity.compact,
                icon: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined, size: 18),
                onPressed: () => setState(() => _editing = !_editing),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            i.human,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (!_editing) ...[
            Text(_prompt.text, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.codeBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('schedule: ${_schedule.text}', style: mono),
            ),
          ] else ...[
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What Hermes runs',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _schedule,
              style: mono,
              decoration: const InputDecoration(
                labelText: 'Schedule (cron, every 2h, 30m, or ISO time)',
                isDense: true,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.danger),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : widget.onSendAsMessage,
                child: const Text('Just send it'),
              ),
              TextButton(
                onPressed: _busy ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _busy ? null : _confirm,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Schedule'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Creates the cron job and drops a short confirmation into the chat.
Future<void> createScheduledTask(
  HermesMobileBackend backend,
  ChatController? chat,
  String originalText,
  ScheduleIntent intent,
) async {
  await backend.createCron(
    name: intent.name,
    schedule: intent.schedule,
    prompt: intent.prompt,
  );
  if (chat != null) {
    chat.wave1AddLocal([
      HermesMobileMessage(role: HermesMobileRole.user, text: originalText),
      HermesMobileMessage(
        role: HermesMobileRole.assistant,
        text:
            'Scheduled **${intent.name}**: ${intent.human} '
            '(`${intent.schedule}`). You can pause or edit it under '
            'Profile → Scheduled tasks.',
      ),
    ]);
  }
}

/// Shows the preview in a sheet. Resolves to the user's choice, or null.
Future<SchedulePreviewChoice?> showSchedulePreview(
  BuildContext context, {
  required ScheduleIntent intent,
  required HermesMobileBackend backend,
  required String originalText,
  ChatController? chat,
}) {
  return showModalBottomSheet<SchedulePreviewChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.viewInsetsOf(c).bottom,
      ),
      child: SafeArea(
        child: SchedulePreviewCard(
          intent: intent,
          onConfirm: (i) async {
            await createScheduledTask(backend, chat, originalText, i);
            if (c.mounted) Navigator.pop(c, SchedulePreviewChoice.created);
          },
          onSendAsMessage: () =>
              Navigator.pop(c, SchedulePreviewChoice.sendAsMessage),
          onCancel: () => Navigator.pop(c),
        ),
      ),
    ),
  );
}
