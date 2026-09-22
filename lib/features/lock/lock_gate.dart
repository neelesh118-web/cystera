import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lock/lock_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_mark.dart';
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
    //
    // The key below is load-bearing, not decoration. A Navigator hands its page
    // to a route once and the route's scope caches it, and `onGenerateRoute` is
    // not re-run for a route that already exists — so a Navigator that keeps its
    // identity across a phase change keeps painting the screen it was born with.
    // Keying it by the phase makes each transition build a fresh Navigator, and
    // therefore a fresh page: without it the app's very first frame (`starting`)
    // is the only screen a launch ever shows, which is a boot splash that never
    // ends on every phone, both when there is no record and when there is one.
    return screen == null
        ? widget.child
        : _ModalNavigator(key: ValueKey(phase), child: screen);
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
  const _ModalNavigator({super.key, required this.child});

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
///
/// It is deliberately the same drawing as the platform's own launch window: the
/// ramp, and the mark, in the same places. Android paints that screen before
/// Flutter exists (`values/styles.xml` and `values-v31/styles.xml`), so matching it
/// is what makes the handover from the platform to this frame invisible. The
/// version this replaced was a small rounded tile on the page background, so a
/// launch went crimson splash → rose tile on paper → the app, which is three
/// screens in half a second and reads as a flicker rather than as an arrival.
///
/// The mark is [AppMark], which is the same geometry as the launcher icon, so all
/// three — the icon, the platform's splash and this — are one mark.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      // No `SafeArea`, and the gradient as the body rather than inside a centred
      // box: the launch window covers the whole panel, status bar included, and a
      // splash that started below the status bar would jump at the handover.
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [t.gradientStart, t.gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppMark(size: 88),
              const SizedBox(height: 28),
              Text(
                'Cystera',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
