import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's mark, drawn: a cycle ring with an opening, and a dot in the opening.
///
/// It is the same drawing as the launcher icon — the same five numbers, in the same
/// 108-unit canvas — which is the point: the thing on the home screen and the thing
/// on the splash and the thing beside a header are one mark rather than three
/// approximations of one. The vector drawables next to `tool/make_icons.py` are the
/// third copy, and each of the three names the other two, because a mark that
/// silently disagrees with itself is worse than any of the three alone.
///
/// Why a painter rather than an asset: this mark is drawn white at 20px beside a
/// header, at 84px on the splash, and (in the icon) at 192px. A PNG would need a
/// size for each and would land between them at every other size, and a vector
/// asset would mean adding `flutter_svg` to an app whose entire dependency story is
/// deliberately short. Twelve lines of `CustomPaint` cost nothing and are always
/// crisp.
class AppMark extends StatelessWidget {
  const AppMark({
    super.key,
    this.size = 72,
    this.color = Colors.white,
  });

  /// The width and height of the square the mark is drawn in.
  final double size;

  /// The mark's colour. The ring and the dot are always the same colour: the dot is
  /// part of the ring's stroke that happens to have come loose, not a second thing.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(color),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);

  final Color color;

  // The canvas the geometry is expressed in, matching the drawables and the icon
  // script. Not a `const` because `math.pi` is not one.
  static const double _canvas = 108;
  static const double _radius = 22;
  static const double _stroke = 11;
  static const double _dotRadius = 6.5;
  static const double _gapCentre = -45 * math.pi / 180; // the top-right
  static const double _gapHalfWidth = 55 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / _canvas;
    final centre = Offset(size.width / 2, size.height / 2);

    // The opening is what makes this a cycle rather than a circle, so the arc is
    // drawn from one edge of the gap to the other and the caps are round — a square
    // cap at this stroke width reads as a notch cut out of a closed ring.
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke * unit
      ..strokeCap = StrokeCap.round;

    final sweep = 2 * math.pi - _gapHalfWidth * 2;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: _radius * unit),
      _gapCentre + _gapHalfWidth,
      sweep,
      false,
      ring,
    );

    // The dot: the next period, not yet arrived. Drawn at the ring's own radius so
    // it sits *in* the opening rather than inside the ring.
    canvas.drawCircle(
      centre + Offset(math.cos(_gapCentre), math.sin(_gapCentre)) * (_radius * unit),
      _dotRadius * unit,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
