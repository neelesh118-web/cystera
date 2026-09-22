import 'package:flutter/material.dart';

import '../../core/log/severity.dart';
import '../../core/theme/app_theme.dart';

/// The one-tap severity control: three targets, one row, no slider.
///
/// Two details are doing the work here.
///
/// **The selected level is a filled block, not a thin outline.** Someone logging
/// on a bad day should be able to see at a glance what they already said, and an
/// outline is the first thing to disappear in daylight on a phone at 40% brightness.
///
/// **The whole row is one target per level, not a track you drag.** A drag needs
/// aim and a steady hand; a tap needs neither, and the value is coarse by design
/// (see `Severity`). The unselected levels are still tappable and still full
/// height, so correcting an entry is the same gesture as making it.
class SeverityRamp extends StatelessWidget {
  const SeverityRamp({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.enabled = true,
    this.levels = Severity.values,
    this.wordFor,
    this.rampIndexFor,
  });

  /// Null means "not logged", which is drawn as the row of empty targets rather
  /// than as a fourth state.
  final Object? value;

  /// Called with the level that was tapped — including when it is the level
  /// already set, which the caller turns into a clear.
  ///
  /// It is deliberately *not* called with null for that case. An earlier version
  /// signalled the clear by passing null, and the symptom row's handler ignored
  /// null, so tapping the same level twice did nothing at all: the one gesture the
  /// whole screen is built on was broken by a type check in a callback.
  final void Function(Enum level) onChanged;

  /// What this row is about, for a screen reader: "Acne, severity". Without it
  /// the three targets announce themselves as "one, two, three", which is
  /// meaningless out of context.
  final String semanticLabel;

  final bool enabled;

  /// Defaults to the [Severity] scale; the flow control passes [FlowLevel] instead so
  /// the same control reads "Light / Medium / Heavy".
  final List<Enum> levels;

  final String Function(Enum level)? wordFor;
  final int Function(Enum level)? rampIndexFor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      label: semanticLabel,
      child: Row(
        children: [
          for (final level in levels)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: level == levels.last ? 0 : 6),
                child: _Target(
                  label: (wordFor ?? _defaultWord)(level),
                  selected: _levelOf(level) == _valueLevel,
                  // The ramp climbs blush → rose → crimson rather than switching
                  // to a traffic light: a severe symptom is not an error, and a
                  // mild one is not success.
                  color: t.severity[((rampIndexFor ?? _defaultRamp)(level))
                      .clamp(0, t.severity.length - 1)],
                  onTap: enabled ? () => onChanged(level) : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  int? get _valueLevel => switch (value) {
        final Severity severity => severity.level,
        final FlowLevel flow => flow.level,
        _ => null,
      };

  int _levelOf(Enum level) => switch (level) {
        final Severity severity => severity.level,
        final FlowLevel flow => flow.level,
        _ => 0,
      };

  static String _defaultWord(Enum level) =>
      level is Severity ? level.word : level is FlowLevel ? level.word : level.name;

  static int _defaultRamp(Enum level) => switch (level) {
        final Severity severity => severity.rampIndex,
        final FlowLevel flow => flow.rampIndex,
        _ => 0,
      };
}

class _Target extends StatelessWidget {
  const _Target({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final disabled = onTap == null;

    return Material(
      color: selected ? color : t.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: selected ? color : t.border,
              width: 1.3,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              // On a filled target the text colour depends on how dark the fill
              // is, which is what `severityLabelOn` is for: the light end of the
              // ramp cannot carry white text.
              color: disabled
                  ? t.textFaint
                  : selected
                      ? _onColor(context, color)
                      : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// Picks the readable ink for a filled ramp colour.
  ///
  /// The ramp runs from a pale blush to a deep crimson, and the same text colour
  /// cannot work on both ends: white on blush fails contrast, and charcoal on
  /// crimson does too. Contrast ratio is the deciding factor, not taste.
  Color _onColor(BuildContext context, Color fill) {
    return fill.computeLuminance() > 0.45 ? Rose.charcoal : Rose.white;
  }
}
