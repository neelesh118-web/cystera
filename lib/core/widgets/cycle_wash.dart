import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// The app's signature element: a slow crimson→rose wash that drifts behind the
/// Today header.
///
/// Two constraints shaped it. First, it has to be *ambient* — a healing-adjacent
/// app that pulses would be exhausting, so the period is 16 seconds and the
/// movement is a few percent of the viewport, not a sweep. Second, it has to
/// stop entirely when the user has asked the system to remove animations: the
/// widget then paints one static frame of the same gradient, so the design is
/// unchanged but nothing moves.
class CycleWash extends StatefulWidget {
  const CycleWash({super.key, this.height = 190, this.child});

  /// The *minimum* height, not a fixed one. A fixed header clips its content, and
  /// the content here is the one line telling the user what is recorded — so a
  /// wrapped headline on a narrow phone, or at a large text scale, would be
  /// silently cut off. The wash paints over whatever height the child needs.
  final double height;

  final Widget? child;

  @override
  State<CycleWash> createState() => _CycleWashState();
}

class _CycleWashState extends State<CycleWash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.ambient,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not started in `initState` because whether to animate is a property of
    // the MediaQuery, which is not available there — and because the answer can
    // change while the app is running, when the user flips "Remove animations".
    if (prefersReducedMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduced = prefersReducedMotion(context);
    // A single frame of the same gradient when motion is off: `t/2` is where the
    // wash would sit on average, so the static design matches the animated one
    // instead of looking like a different screen.
    final tween = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.height),
        child: Stack(
          // Loose, not expand: the child decides how tall the header is, and the
          // background is positioned to fill whatever that turns out to be.
          fit: StackFit.loose,
          children: [
            Positioned.fill(
              child: reduced
                  ? _wash(t.gradientStart, t.gradientEnd, 0.5)
                  : AnimatedBuilder(
                      animation: tween,
                      builder: (context, _) =>
                          _wash(t.gradientStart, t.gradientEnd, tween.value),
                    ),
            ),
            // A dark scrim so the header text keeps its contrast wherever the
            // gradient happens to be in its cycle.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: t.isDark ? 0.10 : 0.22),
                      Colors.black.withValues(alpha: t.isDark ? 0.34 : 0.42),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.child case final child?)
              Padding(
                padding: const EdgeInsets.all(AppTheme.gutter + 2),
                child: child,
              ),
          ],
        ),
      ),
    );
  }

  Widget _wash(Color start, Color end, double t) {
    // The drift: two soft radials that trade places. `math.sin` keeps the motion
    // continuous at the turn of the cycle, which a `Tween` between alignments
    // would not.
    final phase = math.sin(t * math.pi);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1 + 0.5 * phase, -1),
          end: Alignment(1 - 0.5 * phase, 1),
          colors: [start, end],
        ),
      ),
      child: CustomPaint(painter: _GlowPainter(phase: phase, color: end)),
    );
  }
}

/// Two very soft highlights travelling across the gradient — what makes it read
/// as lit rather than as a flat fill.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: size.height * 1.1));

    canvas.drawCircle(
      Offset(size.width * (0.25 + 0.5 * phase), size.height * 0.15),
      size.height * 1.1,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * (0.85 - 0.4 * phase), size.height * 0.9),
      size.height * 0.9,
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.phase != phase || old.color != color;
}
