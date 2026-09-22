import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The dots that fill as a PIN is typed.
///
/// Dots rather than digits: a PIN typed on a phone is usually typed with someone
/// nearby, and the app that asks for it should not be the reason it is seen.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.filled,
    required this.total,
    this.error = false,
  });

  final int filled;
  final int total;

  /// Drives colour only. The message under the dots is what actually says what
  /// went wrong — colour alone is not an explanation, and it is invisible to
  /// anyone who cannot see it.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled
                    ? (error ? t.accent : t.accentSoft)
                    : Colors.transparent,
                border: Border.all(
                  color: error && i >= filled ? t.accent : t.border,
                  width: 1.6,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A numeric keypad sized for one-handed use during a bad day: large targets,
/// generous spacing, no long-press gestures hiding behind anything.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onDone,
    this.doneEnabled = false,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Null hides the confirm key entirely, which is what the "keep typing" states
  /// want — an always-present button that refuses taps reads as broken.
  final VoidCallback? onDone;
  final bool doneEnabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    Widget key(String label, {VoidCallback? onTap, IconData? icon, bool enabled = true}) {
      return SizedBox(
        width: 78,
        height: 60,
        child: Material(
          color: onTap == null ? Colors.transparent : t.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 4),
            onTap: enabled ? onTap : null,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 22, color: enabled ? t.textPrimary : t.textFaint)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: enabled ? t.textPrimary : t.textFaint,
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: key(digit, onTap: () => onDigit(digit)),
                  ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: key('', onTap: onDone, icon: onDone == null ? null : Icons.check_rounded,
                  enabled: doneEnabled),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: key('0', onTap: () => onDigit('0')),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: key('', onTap: onBackspace, icon: Icons.backspace_outlined),
            ),
          ],
        ),
      ],
    );
  }
}

/// The long-form explanation of what the PIN does and does not protect.
///
/// Shown where the user is deciding, not buried in settings: the trade the app
/// makes is unusual enough that deciding it without the sentence would be unfair.
class PinTradeoffNotice extends StatelessWidget {
  const PinTradeoffNotice({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_outlined, size: 18, color: t.accentSoft),
              const SizedBox(width: 10),
              // Expanded because a fixed-width heading beside an icon overflows
              // the moment the text is longer than expected — in a translation,
              // or at a large text scale.
              Expanded(
                child: Text('What the PIN does',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Your PIN does not just lock the screen. It is part of the key that '
            'decrypts your record, so a phone that is taken or copied still gives '
            'up nothing without it.',
            style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Text(
              'The cost, stated plainly: this app cannot reset a forgotten PIN '
              'and keep your data. A reset that kept the data would be one an '
              'attacker could use too. A backup file, with its own passphrase, is '
              'the only way back — so make one before you rely on this phone.',
              style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
