import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The frame every tab shares: a header slot, an optional title, and a scrolling body.
///
/// It exists so the tabs cannot drift apart in padding or in how they handle the
/// status bar, and so the ambient wash on Today is a slot rather than a special case
/// that other pages are measured against.
///
/// Since the hero landed, every tab passes a [PageHero] as [header] and no `title`:
/// the hero carries the screen's name, and a second heading under it was a row that
/// said the same word twice. `title` and `subtitle` are still here for the screens
/// that genuinely want a heading *under* a hero — a section page, or a screen whose
/// hero is not the top of a tab.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.header,
    this.actions,
  });

  /// The screen's name, when the header is not carrying it. Null on the four tabs,
  /// where the hero header carries it instead.
  final String? title;
  final String? subtitle;
  final List<Widget> children;

  /// Rendered edge-to-edge above the padded content, under the status bar.
  final Widget? header;

  /// Trailing actions for the title row. Ignored when there is no title row.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final top = MediaQuery.paddingOf(context).top;
    // Whether there is a heading *under* the header. When the header already carries
    // the name, this is false and the body starts straight after the hero.
    final hasTitleRow = title != null || (actions?.isNotEmpty ?? false);

    return SafeArea(
      top: false,
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(
          top: header == null ? top + 16 : top + 10,
          bottom: MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
              child: header,
            ),
          if (hasTitleRow)
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppTheme.gutter,
                header == null ? 0 : 22,
                AppTheme.gutter,
                0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title case final title?)
                          Text(title, style: Theme.of(context).textTheme.displaySmall),
                        if (subtitle case final subtitle?) ...[
                          const SizedBox(height: 6),
                          Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 14)),
                        ],
                      ],
                    ),
                  ),
                  ...?actions,
                ],
              ),
            ),
          // Tighter after a hero than it used to be: the hero is already a large
          // block, and the old 20-point gap under a title row read as a hole when
          // the title row was not there.
          SizedBox(height: header == null ? 20 : 18),
          for (final child in children)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.gutter,
                0,
                AppTheme.gutter,
                14,
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}
