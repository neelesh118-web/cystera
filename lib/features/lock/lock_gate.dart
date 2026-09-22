import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lock/lock_controller.dart';
import '../../core/theme/app_theme.dart';
import 'lock_screen.dart';
import 'setup_screen.dart';

/// Decides what the user can see, from the lock phase alone.
///
/// It sits inside `MaterialApp` and above the router, so no route can be reached
/// — not by a deep link, not by a restored state — while the key is not in
/// memory. That is the whole point: gating each screen individually would mean
/// relying on every screen remembering to.
///
/// It also owns the lifecycle hook, so auto-lock happens even if no screen is
/// listening.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = context.read<LockController>();
    unawaited(controller.handleLifecycle(state));
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<LockController>().phase;

    final screen = switch (phase) {
      LockPhase.starting => const _Splash(),
      LockPhase.needsSetup => const SetupScreen(),
      LockPhase.locked => const LockScreen(),
      LockPhase.corrupt => const CorruptRecordScreen(),
      LockPhase.unlocked => null,
    };

    // The gate lives in `MaterialApp.builder`, which is *above* the app's own
    // Navigator — so a lock screen that calls showDialog would throw "context
    // does not include a Navigator". Giving the lock screens their own Navigator
    // fixes that, and keeps them unable to reach any app route: the routes are
    // in a different Navigator entirely.
    return screen == null ? widget.child : _ModalNavigator(child: screen);
  }
}

/// A Navigator for the lock screens, so a lock screen can open a dialog.
///
/// The route is a zero-duration [PageRouteBuilder] rather than a
/// [MaterialPageRoute], and that is not a style choice: a Material route animates
/// in, and on a device whose render surface stops producing frames the animation
/// never advances, leaving the lock screen invisible at the start of its own
/// transition. A zero-duration route has no start position to be stuck at, so the
/// screen is on the first frame whatever the GPU does — the same screen the user
/// sees on hardware where the animation would have run.
class _ModalNavigator extends StatelessWidget {
  const _ModalNavigator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => child,
      ),
    );
  }
}

/// Shown while the vault is being read — a second or two at most, but showing
/// the lock screen during it would flash a PIN pad at someone who has no PIN.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.gradientStart, t.gradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Cystera',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
