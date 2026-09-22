import 'package:flutter/material.dart';

import '../../core/crypto/pin.dart';
import '../../core/i18n/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../lock/pin_widgets.dart';

/// A heading over a run of sections.
///
/// The settings page is fourteen cards, and fourteen equal cards is not a page a
/// person can scan — it is a page they scroll until something looks familiar. These
/// headings name the runs without moving anything, so a user who wants the theme
/// knows it is in the first block and a user who wants their backup knows it is
/// under the fifth, and neither has to read the other four to find out.
///
/// The mark beside the words is the app's accent bar rather than an icon: an icon
/// per group would be six more drawings to keep in step with nothing, and a
/// two-pixel rule does the same job of saying "a new subject starts here".
class SettingsGroupHeading extends StatelessWidget {
  const SettingsGroupHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      // Extra room above, and none below: the heading belongs to what follows it,
      // and `PageScaffold` already spaces it from the section underneath.
      padding: const EdgeInsets.only(top: 18, left: 4, right: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 17,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled card of rows. Material rather than a decorated box because ListTile
/// paints its ripples on the nearest Material ancestor.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.label,
    required this.children,
    this.footnote,
  });

  final String label;
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: t.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: BorderSide(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              ...children,
              const SizedBox(height: 6),
            ],
          ),
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              footnote!,
              style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.5),
            ),
          ),
      ],
    );
  }
}

/// A row with a switch and a long explanation.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      secondary: icon == null ? null : Icon(icon, size: 20, color: t.textSecondary),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(
        detail,
        style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
      ),
    );
  }
}

/// Asks for a PIN twice, with the same pad the lock screen uses.
///
/// Returns the chosen PIN, or null if the user backed out. Validation uses
/// [PinPolicy], so the rules are identical wherever a PIN is set.
Future<String?> askForNewPin(BuildContext context, {required String title}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _NewPinDialog(title: title),
  );
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog({required this.title});

  final String title;

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  String _entered = '';
  String? _firstPin;
  String? _problem;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final confirming = _firstPin != null;
    final canSubmit = _entered.length >= PinPolicy.minLength;

    return AlertDialog(
      title: Text(confirming ? text.enterItAgain : widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PinDots(
              filled: _entered.length,
              total: PinPolicy.recommendedLength,
              error: _problem != null,
            ),
            const SizedBox(height: 12),
            Text(
              _problem ??
                  (confirming ? text.pinConfirmHint : text.pinIntro),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _problem != null ? t.accent : t.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            PinPad(
              onDigit: (digit) {
                if (_entered.length >= PinPolicy.maxLength) return;
                setState(() {
                  _entered += digit;
                  _problem = null;
                });
              },
              onBackspace: () => setState(() {
                if (_entered.isNotEmpty) {
                  _entered = _entered.substring(0, _entered.length - 1);
                }
                _problem = null;
              }),
              onDone: canSubmit ? _submit : null,
              doneEnabled: canSubmit,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(text.cancel),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: Text(confirming ? text.save : text.nextLabel),
        ),
      ],
    );
  }

  void _submit() {
    if (_firstPin == null) {
      final problem = PinPolicy.validate(_entered);
      if (problem != null) {
        setState(() => _problem = problem);
        return;
      }
      setState(() {
        _firstPin = _entered;
        _entered = '';
      });
      return;
    }

    if (_entered != _firstPin) {
      setState(() {
        _problem = AppTextScope.of(context).pinMismatch;
        _entered = '';
        _firstPin = null;
      });
      return;
    }

    Navigator.of(context).pop(_entered);
  }
}

/// Confirms something that cannot be undone, with the consequence spelled out.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  // Read before the dialog opens: the `context` below is the caller's, and reading
  // the scope through the dialog's own context after it is pushed is the kind of
  // thing that works until the sheet is rebuilt above a different navigator.
  final text = AppTextScope.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
