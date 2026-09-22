import 'package:flutter/material.dart';

/// One motion vocabulary for the whole app, so the brand feels like one thing
/// rather than a collection of screens that each animate differently.
class Motion {
  Motion._();

  /// Tab switches and page pushes. Fast enough to feel instant, slow enough
  /// that the eye can follow where the screen went.
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 240);

  /// The header wash. Deliberately far slower than any UI transition: it should
  /// read as ambient, never as something demanding attention.
  static const ambient = Duration(seconds: 16);

  static const easeOut = Curves.easeOutCubic;

  /// A gentle overshoot on confirmations (a logged symptom, a saved entry).
  static const settle = Cubic(0.2, 0.9, 0.2, 1.05);
}

/// Whether the user has asked the system to remove animations.
///
/// Every animation in the app must consult this. Android and iOS both expose it
/// (it is what "Remove animations" and "Reduce motion" set), and for an app used
/// during a bad symptom day, movement can be the difference between usable and
/// not.
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// A duration that collapses to zero when animations are off.
Duration respectingMotion(BuildContext context, Duration duration) =>
    prefersReducedMotion(context) ? Duration.zero : duration;
