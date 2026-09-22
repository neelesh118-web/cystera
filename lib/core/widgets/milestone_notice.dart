import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// States plainly what a screen does not do yet, and what it will do.
///
/// Every tab in this milestone uses it instead of inventing sample data. Two
/// reasons: a health app that shows a fabricated cycle or a made-up count is
/// lying to the person reading it, and screenshots of fake data have a way of
/// reaching a store listing. The card is meant to be deleted as each screen is
/// built for real, so it is deliberately easy to find — see `PLANNED` below.
class MilestoneNotice extends StatelessWidget {
  const MilestoneNotice({
    super.key,
    required this.title,
    required this.body,
    this.planned = const <String>[],
  });

  final String title;
  final String body;

  /// What this screen will do, one line each. Written as commitments rather
  /// than as feature names, so it stays honest after the build moves on.
  final List<String> planned;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.construction_outlined, size: 18, color: t.accentSoft),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(body, style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.5)),
          if (planned.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 14),
            for (final line in planned)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 10),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: t.accentSoft,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
