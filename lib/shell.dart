import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/i18n/app_text.dart';

/// One tab: where it goes, what it is called, and its icon.
///
/// The label is built from [AppText] at build time rather than stored as a `const`,
/// because a const string is a string that cannot be translated. The path and the
/// icon stay constant — they are not language.
typedef _Tab = ({String path, String label, IconData icon});

/// The five tabs, in the order they appear.
///
/// Today is first because the app's job is one tap on a bad day; Settings is
/// last because it is the only tab nobody needs daily. The list is the single
/// source of truth for both the bar and the index lookup, so adding a tab cannot
/// leave the highlight pointing at the wrong destination.
List<_Tab> _tabsFor(AppText text) => [
      (path: '/today', label: text.navToday, icon: Icons.today_outlined),
      (path: '/log', label: text.navLog, icon: Icons.add_circle_outline),
      (path: '/cycle', label: text.navCycle, icon: Icons.calendar_month_outlined),
      (path: '/trends', label: text.navTrends, icon: Icons.show_chart_outlined),
      (path: '/settings', label: text.navSettings, icon: Icons.settings_outlined),
    ];

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tabs = _tabsFor(AppTextScope.of(context));
    // An unknown or nested route falls back to Today rather than to index 0 by
    // accident — the two happen to be the same today, but not by construction.
    final index = tabs.indexWhere((t) => location == t.path);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}
