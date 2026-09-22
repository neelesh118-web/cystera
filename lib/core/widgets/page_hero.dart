import 'package:flutter/material.dart';

import 'app_mark.dart';
import 'cycle_wash.dart';

/// The block at the top of every tab: the app's wash, the mark, a small line, a big
/// line, and one supporting line.
///
/// It exists because the tabs had five different headers. Today had the wash and a
/// headline; the other four had a plain dark title on the page background, so the
/// app's one strong piece of design appeared on a fifth of its screens and the rest
/// began as a list. A user moving between tabs saw a different product each time —
/// which is most of what "cluttered" turns out to mean here.
///
/// The hero carries the destination's name, so a page no longer needs a title row
/// under it: see [PageScaffold], which drops its own title when a hero is passed.
/// That is one less heading per screen, and the five screens now agree about where
/// the screen's name goes.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.footer,
    this.trailing,
    this.mark = true,
    this.height = 150,
  });

  /// The destination's own name, usually — the big line.
  ///
  /// A widget rather than a string because Today puts two lines here: the date in
  /// small type, then the honest headline ("Nothing recorded yet") under it. That
  /// pairing is the whole design of that screen and does not generalise, so the slot
  /// takes a widget and the other four pass one [Text].
  final Widget title;

  /// A small line above the title. Rendered upper-case; kept as typed so a
  /// translated label is not shouted at in its own script.
  final String? overline;

  /// One line under the title explaining what the screen is for.
  final String? subtitle;

  /// A row under the text — where the Patterns switcher sits.
  final Widget? footer;

  /// A control on the overline's row, right-aligned. Used by the Log screen for
  /// "Back to today".
  final Widget? trailing;

  /// Whether to draw the app mark beside the overline. On by default: it is what
  /// ties five different screens to one icon.
  final bool mark;

  /// The *minimum* height of the wash, as on [CycleWash]: the content decides.
  final double height;

  @override
  Widget build(BuildContext context) {
    return CycleWash(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (mark) ...[
                AppMark(size: 18, color: Colors.white.withValues(alpha: 0.92)),
                const SizedBox(width: 9),
              ],
              // Bound to a local rather than read off the field: a public field is not
              // promoted, and the alternative is a `!` in the one place a null would
              // draw nothing at all.
              if (overline case final line?)
                Expanded(
                  child: Text(
                    line.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.9,
                    ),
                  ),
                )
              else
                const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 20),
          title,
          if (subtitle case final note?) ...[
            const SizedBox(height: 7),
            Text(
              note,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (footer case final row?) ...[
            const SizedBox(height: 18),
            row,
          ],
        ],
      ),
    );
  }
}

/// The big line in a hero, in the one weight and colour every hero uses.
///
/// Separate from [PageHero] so a page can pass it as the `title` widget without
/// repeating the style, and so the style has one home if it changes.
///
/// It is marked as a heading for a screen reader, which is the one thing a large
/// white line on a gradient cannot say for itself: sighted users see five screens
/// with the same shape and learn it in a minute, while a screen reader hears a
/// subtitle, a number and a sentence in the order they happen to be painted.
/// Marking the heading is what lets someone skip the header of every tab — which
/// is now five identical headers rather than one.
class HeroTitle extends StatelessWidget {
  const HeroTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 27,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          height: 1.15,
        ),
      ),
    );
  }
}
