import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/pin.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/cycle_wash.dart';
import 'pin_widgets.dart';

/// What happens the first time the app is opened.
///
/// The decision this screen asks for is the most consequential one in the app,
/// so it is asked once, in full sentences, with the cost of each answer stated
/// where the answer is given — not in a settings toggle the user finds later.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _Step { choice, createPin, confirmPin }

class _SetupScreenState extends State<SetupScreen> {
  _Step _step = _Step.choice;
  String _firstPin = '';
  String _entered = '';
  String? _problem;
  bool _busy = false;
  bool _restoreMode = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 20, AppTheme.gutter, 28),
          children: switch (_step) {
            _Step.choice => _choiceStep(context, t),
            _Step.createPin => _pinStep(
                context,
                t,
                title: 'Choose a PIN',
                subtitle: 'Four to eight digits. Six is a good balance between '
                    'typing it often and it taking a while to guess.',
                confirmLabel: 'Continue',
              ),
            _Step.confirmPin => _pinStep(
                context,
                t,
                title: 'Enter it again',
                subtitle: 'So a typo does not become the PIN you cannot remember.',
                confirmLabel: 'Save and open',
              ),
          },
        ),
      ),
    );
  }

  List<Widget> _choiceStep(BuildContext context, AppTokens t) {
    return [
      CycleWash(
        // Tall enough for the two-line headline at the largest text scale the
        // app allows. The header is a fixed-height design element, so this
        // number is the thing that keeps it from clipping.
        height: 184,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: const [
            Text(
              'CYSTERA',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'A record that\ncannot be uploaded',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Text(
        'Before you start',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Text(
        'Everything you log stays in an encrypted database on this phone. There '
        'is no account, no server and no analytics, and the app has no internet '
        'permission at all — it cannot send your record anywhere even if it '
        'wanted to.',
        style: TextStyle(color: t.textSecondary, fontSize: 14.5, height: 1.55),
      ),
      const SizedBox(height: 20),
      const PinTradeoffNotice(),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => setState(() {
          _step = _Step.createPin;
          _problem = null;
        }),
        child: const Text('Set a PIN'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: _busy ? null : _continueWithoutPin,
        child: const Text('Continue without a PIN'),
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _restoreMode = !_restoreMode),
        child: Text(_restoreMode ? 'Hide' : 'I already have a backup file'),
      ),
      if (_restoreMode)
        Text(
          'Restoring arrives with the backup screen in this same milestone — '
          'export your first backup from Settings once the record is open.',
          style: TextStyle(color: t.textFaint, fontSize: 13, height: 1.5),
        ),
      const SizedBox(height: 16),
      Text(
        'Without a PIN, the database is still encrypted, but it is protected by '
        'this phone\'s keystore alone. Anyone who can unlock the phone can read '
        'the record.',
        style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.5),
      ),
    ];
  }

  List<Widget> _pinStep(
    BuildContext context,
    AppTokens t, {
    required String title,
    required String subtitle,
    required String confirmLabel,
  }) {
    final policyProblem = PinPolicy.validate(_entered);
    final canConfirm = _entered.length >= PinPolicy.minLength && !_busy;

    return [
      if (_step == _Step.confirmPin)
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _step = _Step.createPin;
                      _entered = '';
                      _problem = null;
                    }),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
      Text(title, style: Theme.of(context).textTheme.displaySmall),
      const SizedBox(height: 8),
      Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.5)),
      const SizedBox(height: 26),
      PinDots(
        filled: _entered.length,
        total: PinPolicy.recommendedLength,
        error: _problem != null,
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 40,
        child: Text(
          _problem ??
              (_entered.isEmpty
                  ? ''
                  : _step == _Step.createPin
                      ? PinPolicy.describeStrength(PinPolicy.strength(_entered))
                      : ''),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _problem != null ? t.accent : t.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ),
      PinPad(
        onDigit: (digit) {
          if (_entered.length >= PinPolicy.maxLength) return;
          setState(() {
            _entered += digit;
            _problem = null;
          });
        },
        onBackspace: () {
          if (_entered.isEmpty) return;
          setState(() {
            _entered = _entered.substring(0, _entered.length - 1);
            _problem = null;
          });
        },
        onDone: canConfirm ? _confirm : null,
        doneEnabled: canConfirm,
      ),
      const SizedBox(height: 12),
      if (_step == _Step.createPin && _entered.isNotEmpty && policyProblem != null)
        Center(
          child: Text(
            policyProblem,
            style: TextStyle(color: t.textFaint, fontSize: 12.5),
          ),
        ),
      const SizedBox(height: 6),
      FilledButton(
        onPressed: canConfirm ? _confirm : null,
        child: Text(confirmLabel),
      ),
      const SizedBox(height: 12),
      if (_step == _Step.createPin)
        Text(
          'Write it down somewhere that is not this phone. Cystera cannot reset a '
          'forgotten PIN and keep your data — the PIN is part of the key.',
          style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.5),
        ),
    ];
  }

  void _confirm() {
    if (_step == _Step.createPin) {
      final problem = PinPolicy.validate(_entered);
      if (problem != null) {
        setState(() => _problem = problem);
        return;
      }
      setState(() {
        _firstPin = _entered;
        _entered = '';
        _step = _Step.confirmPin;
        _problem = null;
      });
      return;
    }

    if (_entered != _firstPin) {
      setState(() {
        _problem = 'Those two did not match. Start again.';
        _entered = '';
        _step = _Step.createPin;
        _firstPin = '';
      });
      return;
    }

    _create(pin: _firstPin);
  }

  Future<void> _create({String? pin}) async {
    setState(() => _busy = true);
    final controller = context.read<LockController>();
    final created = await controller.completeSetup(pin: pin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!created) {
      setState(() => _problem = controller.message ?? 'The record could not be created.');
    }
  }

  Future<void> _continueWithoutPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Continue without a PIN?'),
        content: const Text(
          'Anyone who picks up this unlocked phone can read the whole record. '
          'You can turn the lock on later from Settings, and doing that will not '
          'touch your data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _create();
    }
  }
}
