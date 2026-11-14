import 'package:flutter/widgets.dart';

import '../../chat/chat_controller.dart';
import '../../data/app_state.dart';
import 'w1_attachments.dart';
import 'w1_schedule.dart';
import 'w1_schedule_card.dart';
import 'w1_services.dart';

export 'w1_prompt_cards.dart' show HermesMobilePromptCard;

/// If [text] reads as a scheduling request, shows the cron preview card and
/// returns true (the caller must not send). "Just send it" calls [sendNow].
bool w1InterceptSchedule(
  BuildContext context,
  ChatController chat,
  String text,
  void Function(String text, String? image) sendNow,
) {
  if (chat.running) return false;
  final intent = parseScheduleIntent(text);
  if (intent == null) return false;
  final backend = HermesMobileScope.read(context).backend;
  showSchedulePreview(
    context,
    intent: intent,
    backend: backend,
    originalText: text.trim(),
    chat: chat,
  ).then((choice) {
    if (choice == SchedulePreviewChoice.sendAsMessage) sendNow(text, null);
  });
  return true;
}

/// Uploads composer files through the Petasos plugin (demo: pretend path).
W1Uploader w1Uploader(BuildContext context) {
  final backend = HermesMobileScope.read(context).backend;
  return (name, bytes) => Wave1Services.of(backend).source.upload(name, bytes);
}
