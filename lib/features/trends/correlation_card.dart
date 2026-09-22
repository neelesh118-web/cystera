import 'package:flutter/material.dart';

import '../../core/log/symptom_correlation.dart';
import '../../core/theme/app_theme.dart';

/// The symptom-timing comparison: what cleared the gate, and the gate itself.
///
/// The gate is not a footnote here. A correlation screen that says "stress is
/// linked to your bad days" and leaves the sample size in its own head is a screen
/// that talks people into giving things up, so the thresholds, the counts they were
/// checked against and the days that were held out are all on the card, in the same
/// type as the findings.
class CorrelationCard extends StatelessWidget {
  const CorrelationCard({super.key, required this.correlation});

  final SymptomCorrelation correlation;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = correlation;

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
          Text('SYMPTOM TIMING', style: _eyebrow(t)),
          const SizedBox(height: 12),
          Text(
            _headline(c),
            style: TextStyle(color: t.textPrimary, fontSize: 14, height: 1.5),
          ),
          if (c.hasFindings) ...[
            const SizedBox(height: 16),
            for (var i = 0; i < c.findings.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              _Finding(finding: c.findings[i]),
            ],
          ],
          const SizedBox(height: 18),
          _Facts(correlation: c),
        ],
      ),
    );
  }

  String _headline(SymptomCorrelation c) {
    if (!c.hasFindings) return c.refusal ?? 'Nothing to compare yet.';
    final count = c.cleared;
    // Pluralised on the number *compared*, not on the number that cleared: the
    // first version of this sentence read "1 of the 14 symptom you log", which is
    // what a finder over the whole string is for.
    final symptoms = c.symptomsTested == 1 ? 'symptom' : 'symptoms';
    final lead = '$count of the ${c.symptomsTested} $symptoms you log cleared '
        'the gate below: ${count == 1 ? 'it is' : 'each is'} at least twice as '
        'common in ${c.beforeLabel} as on ${c.otherLabel}.';
    if (!c.capped) return lead;
    return '$lead The strongest ${c.findings.length} are shown — the count above is '
        'the whole number that cleared the gate.';
  }
}

/// One finding: the two rates as numbers and as bars, then the qualifiers.
class _Finding extends StatelessWidget {
  const _Finding({required this.finding});

  final SymptomFinding finding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final f = finding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.symptom.label,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          f.headline,
          style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 10),
        _Bar(
          label: 'Before a ${f.bleedWord}',
          percent: f.before.ratePercent,
          days: f.before.symptomDays,
          of: f.before.days,
          color: t.accent,
        ),
        const SizedBox(height: 8),
        _Bar(
          label: 'Other days',
          percent: f.other.ratePercent,
          days: f.other.symptomDays,
          of: f.other.days,
          color: t.accentSoft,
        ),
        const SizedBox(height: 10),
        Text(
          f.detail,
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

/// A rate, drawn and written. The number is on the bar because a bar alone is a
/// claim the reader cannot check, and every bar here is meant to be checkable.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.percent,
    required this.days,
    required this.of,
    required this.color,
  });

  final String label;
  final int percent;
  final int days;
  final int of;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final share = (percent / 100).clamp(0.0, 1.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.3),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 6,
                  color: t.surfaceRaised,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share,
                    child: Container(color: color),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$percent% — $days of $of logged days',
                style: TextStyle(color: t.textFaint, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The gate, the sample it was applied to, and what was held out.
class _Facts extends StatelessWidget {
  const _Facts({required this.correlation});

  final SymptomCorrelation correlation;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = correlation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: t.border, height: 1),
        const SizedBox(height: 14),
        Text('WHAT THIS IS COMPARED OVER', style: _eyebrow(t)),
        const SizedBox(height: 8),
        Text(
          c.sampleLine,
          style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.5),
        ),
        if (c.heldOutLine case final heldOut?) ...[
          const SizedBox(height: 6),
          Text(
            heldOut,
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
          ),
        ],
        const SizedBox(height: 14),
        Text('THE GATE', style: _eyebrow(t)),
        const SizedBox(height: 8),
        Text(
          CorrelationGate.statement,
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 8),
        Text(
          'A symptom that misses any part of the gate is not shown at all — not '
          'smaller and not greyed out, because a finding shown faintly is still a '
          'finding.',
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 14),
        Text(
          'The only phase boundary used here is the day you recorded a '
          '${c.bleedWord} starting. No ovulation date is estimated, so this is not '
          'a luteal-phase claim — the days before a recorded start need no '
          'assumption about cycle length at all.',
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 10),
        Text(
          'Correlation, not cause. Nothing here says a period causes the symptom, '
          'and nothing can tell whether you noticed a symptom because a period was '
          'coming. What it can tell you is what you logged — on the days you '
          'logged. Foods, sleep, stress and medication are not tested yet.',
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

TextStyle _eyebrow(AppTokens t, {double size = 11.5}) => TextStyle(
      color: t.textFaint,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    );
