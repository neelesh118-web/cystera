import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/i18n/app_text.dart';
import 'core/theme/app_theme.dart';

/// One tab: where it goes, what it is called, and its two icons.
///
/// The label is built from [AppText] at build time rather than stored as a `const`,
/// because a const string is a string that cannot be translated. The path and the
/// icons stay constant — they are not language.
///
/// [paths] is a list because one destination can be two routes: Patterns holds the
/// cycle and the trends, and the bar has to stay lit for either of them. The list is
/// also what makes the highlight impossible to get wrong — the index is found by
/// asking which tab claims the current location, not by comparing strings and hoping
/// the omission is noticed.
typedef _Tab = ({
  String path,
  List<String> paths,
  String label,
  IconData icon,
  IconData selectedIcon,
});

/// The four destinations, in the order they appear.
///
/// Four, down from five. Today is first because the app's job is one tap on a bad
/// day; Settings is last because it is the only tab nobody needs daily. The cycle
/// and the trends merged into Patterns — see [PatternsSwitcher] — which is what took
/// the bar from five places, where two of them were the same idea, to four that each
/// hold something distinct.
List<_Tab> _tabsFor(AppText text) => [
      (
        path: '/today',
        paths: ['/today'],
        label: text.navToday,
        icon: Icons.today_outlined,
        selectedIcon: Icons.today,
      ),
      (
        path: '/log',
        paths: ['/log'],
        label: text.navLog,
        icon: Icons.add_circle_outline,
        selectedIcon: Icons.add_circle,
      ),
      (
        path: '/cycle',
        paths: ['/cycle', '/trends'],
        label: text.navPatterns,
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
      ),
      (
        path: '/settings',
        paths: ['/settings'],
        label: text.navSettings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
    ];

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tabs = _tabsFor(AppTextScope.of(context));
    // An unknown or nested route falls back to Today rather than to index 0 by
    // accident — the two happen to be the same today, but not by construction.
    final index = tabs.indexWhere((tab) => tab.paths.contains(location));

    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        // A hairline where the bar meets the page. Without it the bar and the page
        // background are the same colour, so the bar read as floating text rather
        // than as a surface — and on a screen whose last card is the same colour as
        // both, it looked like the card had been cut off.
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.border)),
        ),
        child: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) => context.go(tabs[i].path),
          destinations: [
            for (final tab in tabs)
              NavigationDestination(
                icon: Icon(tab.icon),
                // Filled when selected, outlined when not: with four destinations
                // the colour shift alone was easy to miss on a dark theme.
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}
