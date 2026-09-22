import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/app_text.dart';
import '../../core/log/log_controller.dart';

/// Offers the one-level undo after a write, as a toast rather than a dialog.
///
/// "An undo that never asks twice" means exactly this: the write has already
/// happened, the correction is a button in the message that reports it, and at no
/// point is the user asked "are you sure". A confirmation dialog on a one-tap
/// logger would double the taps on the screen that exists to have one.
///
/// The description comes from the controller rather than from the caller, so the
/// sentence describing what happened and the action that reverses it are written
/// by the same code that did it — which is the only way they cannot disagree.
void offerUndo(BuildContext context, LogController log) {
  final undo = log.undo;
  final description = log.lastDescription;
  final error = log.error;
  if (undo == null || description == null) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(error ?? description),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          // Read here rather than passed in: the action is drawn by the messenger,
          // which is above the page, so this is the one place that has the context
          // the label needs.
          label: AppTextScope.of(context).undo,
          onPressed: () => unawaited(undo()),
        ),
      ),
    );
}

/// A write plus its undo offer, so a caller cannot forget the second half.
///
/// Returns nothing on purpose: whether the write succeeded is already in
/// [LogController.error], and a second boolean would be a second answer to the
/// same question.
Future<void> writeAndOfferUndo(
  BuildContext context,
  LogController log,
  Future<void> Function() write,
) async {
  await write();
  if (!context.mounted) return;
  offerUndo(context, log);
}
