import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The frame every tab shares: a header slot, a title, and a scrolling body.
///
/// It exists so the five tabs cannot drift apart in padding or in how they
/// handle the status bar, and so the ambient wash on Today is a slot rather
/// than a special case that other pages are measured against.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.header,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Rendered edge-to-edge above the padded content, under the status bar.
  final Widget? header;

  /// Trailing actions for the title row.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final top = MediaQuery.paddingOf(context).top;

    return SafeArea(
      top: false,
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(
          top: header == null ? top + 16 : top + 8,
          bottom: MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
              child: header,
            ),
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
                      Text(title, style: Theme.of(context).textTheme.displaySmall),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(subtitle!, style: TextStyle(color: t.textSecondary, fontSize: 14)),
                      ],
                    ],
                  ),
                ),
                ...?actions,
              ],
            ),
          ),
          const SizedBox(height: 20),
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
