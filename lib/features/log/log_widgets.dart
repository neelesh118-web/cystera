import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The card every section of the logging screen is made of.
///
/// Shared rather than private to the log page because the medication section lives
/// in its own file and has to look identical to the symptom domains beside it: a
/// second card implementation is how two sections of one screen start drifting apart
/// in padding, in heading weight or in how they explain themselves.

class LogCard extends StatelessWidget {
  const LogCard({
    super.key,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.children,
  });

  final String title;
  final String blurb;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: t.accentSoft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(blurb, style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
