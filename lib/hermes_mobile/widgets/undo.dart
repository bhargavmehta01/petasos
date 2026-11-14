import 'dart:async';

import 'package:flutter/material.dart';
import '../features/wave2_parity/w2_settings.dart';

/// How long an Undo snackbar stays up.
const kUndoWindow = Duration(seconds: 6);

/// The outcome of an undo window.
enum UndoOutcome { undone, committed }

/// One deferred action: [commit] runs once when the window closes without
/// Undo; [undo] runs once when the user taps Undo. Whichever comes first wins
/// and the other becomes a no-op, so a late snackbar callback can never run
/// both. Pure logic, no widgets, so it is unit-testable.
class PendingUndo {
  PendingUndo({required this.undo, this.commit});

  final FutureOr<void> Function() undo;
  final FutureOr<void> Function()? commit;
  UndoOutcome? _outcome;

  UndoOutcome? get outcome => _outcome;
  bool get settled => _outcome != null;

  Future<void> runUndo() async {
    if (settled) return;
    _outcome = UndoOutcome.undone;
    await undo();
  }

  Future<void> runCommit() async {
    if (settled) return;
    _outcome = UndoOutcome.committed;
    await commit?.call();
  }
}

/// Shows "[message]  Undo" for [duration]. Tapping Undo calls [onUndo];
/// any other close (timeout, swipe, another snackbar, the screen going away)
/// calls [onCommit]. Use [onCommit] for the server-side half of the action so
/// nothing irreversible happens while Undo is still on screen.
///
/// When there is no ScaffoldMessenger the action commits right away.
PendingUndo showUndoSnackBar(
  BuildContext context, {
  required String message,
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onCommit,
  Duration duration = kUndoWindow,
}) {
  final pending = PendingUndo(undo: onUndo, commit: onCommit);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    unawaited(pending.runCommit());
    return pending;
  }
  messenger.hideCurrentSnackBar();
  final ctl = messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      // Undo snackbars must time out even with an action (Flutter keeps
      // action snackbars up by default on some versions).
      persist: false,
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          W2Haptics.selection();
          unawaited(pending.runUndo());
        },
      ),
    ),
  );
  ctl.closed.then((reason) {
    if (reason == SnackBarClosedReason.action) {
      unawaited(pending.runUndo());
    } else {
      unawaited(pending.runCommit());
    }
  });
  return pending;
}

/// A plain, consistent confirmation snackbar (no action).
void showHermesMobileSnack(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
