import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../i18n/app_text.dart';
import '../theme/app_theme.dart';

/// The two views inside the Patterns destination: the cycle, and the trends.
///
/// These were two of the app's five tabs, which meant the bar spent two of its five
/// places on one idea — the record read over time — and left the user to work out
/// which of the two held the thing they wanted. They are now one destination with a
/// switcher at the top of each view, so both are one tap away and the bar has a
/// place back that a fifth of the app's navigation was taking.
///
/// Two routes rather than one screen with a state flag, deliberately: `/cycle` and
/// `/trends` are what the Today card links to, what a test opens, and what a
/// restored session lands on. Merging the *destination* while keeping the routes
/// means nothing that already pointed at either screen had to learn a new address.
///
/// The labels are the two labels the bar used to carry, still read from `AppText`:
/// a switcher whose segments are translated while its neighbours are not would be
/// the worst of both.
class PatternsSwitcher extends StatelessWidget {
  const PatternsSwitcher({super.key, required this.current});

  /// The route the user is on: `/cycle` or `/trends`.
  final String current;

  @override
  Widget build(BuildContext context) {
    final text = AppTextScope.of(context);
    final segments = <({String path, String label})>[
      (path: '/cycle', label: text.navCycle),
      (path: '/trends', label: text.navTrends),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // A dark translucent well rather than a light one: the hero behind this is
        // the app's crimson-to-rose ramp, which is lighter at the bottom, and a white
        // well would leave the unselected label fighting the gradient for contrast.
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          for (final segment in segments)
            Expanded(
              child: _Segment(
                label: segment.label,
                selected: segment.path == current,
                onTap: () => context.go(segment.path),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Tapping the view you are already on is a no-op rather than a rebuild:
          // `go` to the current location would push a second copy of the route.
          onTap: selected ? null : onTap,
          child: Container(
            // A minimum rather than a fixed height. The app allows the system text
            // scale up to 1.3 (`app.dart`), and at that size the longest of the two
            // labels wraps in some languages — a 38-point box would then draw the
            // second line over the pill's own border.
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            alignment: Alignment.center,
            child: Text(
              textAlign: TextAlign.center,
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? t.accent : Colors.white.withValues(alpha: 0.94),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
