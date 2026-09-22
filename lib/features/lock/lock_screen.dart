import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/pin.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/widgets/app_mark.dart';
import 'pin_widgets.dart';

/// The screen between someone holding the phone and the record.
///
/// Three things it does that a lock screen often gets wrong, all of them because
/// this app's users are not always in a state to fight with software:
///
/// * it says how many attempts are left before a pause, rather than surprising
///   someone with a lockout they did not know was coming;
/// * it counts the pause down in seconds, so the number is a fact and not a
///   spinner;
/// * it explains what to do next when the PIN is genuinely gone, instead of
///   offering "try again" forever.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entered = '';
  Timer? _ticker;
  bool _busy = false;

  /// Shown once a PIN has been submitted and refused, so the dots change colour.
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    // One ticker, running only while there is something to count down.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final controller = context.read<LockController>();
      setState(() {});
      if (controller.lockoutRemaining == null) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _addDigit(String digit) {
    if (_busy) return;
    final controller = context.read<LockController>();
    if (controller.lockoutRemaining != null) return;
    if (_entered.length >= PinPolicy.maxLength) return;

    setState(() {
      _entered += digit;
      _refused = false;
    });

    // Submitting at the maximum length only. A shorter PIN still needs the
    // confirm key, because the app does not store how long the PIN is — storing
    // it would tell an attacker exactly how many digits to try.
    if (_entered.length == PinPolicy.maxLength) {
      unawaited(_submit());
    }
  }

  void _backspace() {
    if (_busy || _entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _refused = false;
    });
  }

  Future<void> _submit() async {
    if (_entered.isEmpty || _busy) return;
    final pin = _entered;
    final controller = context.read<LockController>();

    setState(() => _busy = true);
    final unlocked = await controller.unlockWithPin(pin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _entered = '';
      _refused = !unlocked;
    });

    if (!unlocked) {
      final wait = controller.lockoutRemaining;
      if (wait != null && _ticker == null) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {});
        });
      }
    }
  }

  Future<void> _biometric() async {
    setState(() => _busy = true);
    await context.read<LockController>().unlockWithBiometrics();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = context.watch<LockController>();
    final wait = controller.lockoutRemaining;
    final paused = wait != null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 24, AppTheme.gutter, 24),
          children: [
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.gradientStart, t.gradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                // The mark, at the size the launcher draws it inside its own mask:
                // `AppMark` fills 51% of this box, which is what the adaptive icon's
                // foreground does on a 108 canvas. So this is the artwork of the
                // icon the user just tapped, on the screen that icon opened.
                //
                // It was a blank gradient tile. On the one screen nobody can avoid
                // — every launch, every return from the background — a plain square
                // of the app's colours is exactly what a placeholder looks like.
                child: const AppMark(size: 58),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              paused ? 'Paused' : 'Your record is locked',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              paused
                  ? 'A pause after repeated wrong PINs. It ends on its own — nothing has been lost.'
                  : 'Enter your PIN to open it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 26),
            PinDots(
              filled: _entered.length,
              // The app does not store how long the PIN is, so the dots cannot
              // say how many are left. They show a comfortable minimum and grow
              // while the user types — which is why the confirm key exists,
              // instead of guessing when a short PIN is finished.
              total: (_entered.length + 1)
                  .clamp(PinPolicy.recommendedLength, PinPolicy.maxLength),
              error: _refused,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: AnimatedOpacity(
                duration: respectingMotion(context, Motion.fast),
                opacity: controller.message == null ? 0 : 1,
                child: Text(
                  paused
                      ? '${wait.inMinutes > 0 ? '${wait.inMinutes} min ' : ''}${wait.inSeconds % 60}s'
                      : controller.message ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _refused ? t.accent : t.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            PinPad(
              onDigit: _addDigit,
              onBackspace: _backspace,
              onDone: _entered.isEmpty ? null : () => unawaited(_submit()),
              doneEnabled: !_busy && !paused,
            ),
            const SizedBox(height: 8),
            if (controller.prefs.biometricsEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: OutlinedButton.icon(
                  onPressed: _busy || paused ? null : _biometric,
                  icon: const Icon(Icons.fingerprint, size: 20),
                  label: const Text('Use biometrics'),
                ),
              ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: paused ? null : () => _showHelp(context),
              child: const Text('Forgotten the PIN?'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Scrollable and tall-allowed: this sheet is three paragraphs and a button,
      // which does not fit a short phone or a large text scale otherwise.
      isScrollControlled: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 0, AppTheme.gutter, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If the PIN is gone',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final t = context.tokens;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your PIN is part of the key that decrypts the record, so it '
                    'cannot be reset from here — that is what makes the lock real '
                    'rather than decorative.',
                    style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Two ways forward, and both are final:\n\n'
                    '1. Restore a backup file you made earlier. Restoring replaces '
                    'everything currently on this phone.\n'
                    '2. Erase this phone\'s copy and start again. There is no way to '
                    'erase the PIN and keep the record.',
                    style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _confirmErase(context);
                    },
                    child: const Text('Erase everything and start again'),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmErase(BuildContext context) async {
    final controller = context.read<LockController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase this phone\'s copy?'),
        content: const Text(
          'Cycles, symptoms, notes and settings on this phone are deleted. A backup '
          'file you exported earlier is not affected and can be restored afterwards.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it locked'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.eraseEverything();
    }
  }
}

/// Shown when the key material on this phone is unusable.
///
/// A separate screen from the lock screen on purpose: offering a PIN pad to
/// someone whose key is damaged invites them to keep typing a correct PIN that
/// will never work.
class CorruptRecordScreen extends StatelessWidget {
  const CorruptRecordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = context.watch<LockController>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 32, AppTheme.gutter, 24),
          children: [
            Icon(Icons.report_gmailerrorred_outlined, size: 34, color: t.accent),
            const SizedBox(height: 18),
            Text(
              'This phone\'s record cannot be opened',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'The key that decrypts your record is damaged or incomplete. This '
              'usually follows clearing the app\'s data outside the app, restoring '
              'a phone backup, or an interrupted write.\n\n'
              'Your database file is still on the phone and was never readable '
              'without that key, so nothing about it has been exposed.',
              style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.55),
            ),
            if (controller.message != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: t.border),
                ),
                child: Text(
                  controller.message!,
                  style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Erase and start again?'),
                  content: const Text(
                    'Everything on this phone is deleted, including the unreadable '
                    'database. You can then restore a backup file if you have one.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        controller.eraseEverything();
                      },
                      child: const Text('Erase'),
                    ),
                  ],
                ),
              ),
              child: const Text('Erase and start again'),
            ),
          ],
        ),
      ),
    );
  }
}
