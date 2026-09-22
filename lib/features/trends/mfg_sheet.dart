/// Recording one mFG self-check: nine areas, nine answers, no total.
///
/// The sheet is where the expectation of a score actually lives — someone who
/// has read about the check arrives expecting a number back — so this is where
/// [mfgRefusalSheet] says, in full, why none is coming. Everything else is
/// deliberately plain: a day to claim, one row of 0–4 per area, and a save
/// that writes the whole check or nothing.
///
/// Tapping a selected value unmarks the area, the same rule the severity
/// ramps use: a tap on the state already set clears it, so a value picked by
/// mistake is undone by the same tap rather than by hunting for a clear
/// button. An unmarked area is *not rated* — the distinction the whole
/// feature turns on, and the reason nothing here ever preselects zeros.
library;

import 'package:flutter/material.dart';

import '../../core/hirsutism/mfg_models.dart';
import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import '../log/undo_toast.dart';

void showMfgSheet(BuildContext context, LogController log) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.tokens.surface,
    builder: (_) => _MfgSheet(log: log),
  );
}

class _MfgSheet extends StatefulWidget {
  const _MfgSheet({required this.log});

  final LogController log;

  @override
  State<_MfgSheet> createState() => _MfgSheetState();
}

class _MfgSheetState extends State<_MfgSheet> {
  /// Null means today. The day is claimed by hand like every other dated
  /// claim here — backdatable, and refused in the future by the picker and
  /// the controller alike.
  DateTime? _day;

  /// Only the areas actually looked at. Starts empty even on a day the record
  /// holds nothing for: a sheet that opened pre-marked with nine zeros would
  /// record a look nobody took.
  Map<MfgArea, int> _ratings = const {};

  @override
  void initState() {
    super.initState();
    _day = widget.log.today;
    _prefill();
  }

  /// Loads the day's existing check, if any, so opening the sheet on a day
  /// that was already checked *edits* it rather than offering a second,
  /// competing one — a day holds one check, as the replace write says.
  void _prefill() {
    final existing = widget.log.mfgCheckFor(_day ?? widget.log.today);
    _ratings = existing == null ? const {} : Map.of(existing.ratings);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? widget.log.today,
      firstDate: DateTime(2000),
      // A check about a day that has not happened yet is refused here and by
      // the controller alike — the picker's rule is the earlier of the two.
      lastDate: widget.log.today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = picked;
      // A day that already holds a check loads it — the sheet saves whole
      // days, so what is about to be overwritten must be on screen. A day
      // with *no* check keeps the picks already made: they are this person's
      // answers, and moving the claim to the right day must not throw away
      // the look they just took.
      final existing = widget.log.mfgCheckFor(picked);
      if (existing != null) _ratings = Map.of(existing.ratings);
    });
  }

  void _rate(MfgArea area, int value) {
    setState(() {
      final next = {..._ratings};
      if (next[area] == value) {
        next.remove(area);
      } else {
        next[area] = value;
      }
      _ratings = next;
    });
  }

  Future<void> _save() async {
    await writeAndOfferUndo(
      context,
      widget.log,
      () => widget.log.saveMfgCheck(
        day: _day ?? widget.log.today,
        ratings: _ratings,
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final log = widget.log;
    final day = _day ?? log.today;
    // One sentence, three jobs: the hint under the form while nothing is
    // rated, the guard the controller enforces anyway, and the words
    // `docs/mfg.md` quotes and the docs test pins.
    final problem = mfgValidate(_ratings);

    return Padding(
      padding: EdgeInsets.fromLTRB(AppTheme.gutter, 4, AppTheme.gutter, 28),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SELF-CHECK',
              style: TextStyle(
                color: t.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Rate each area you actually looked at, from 0 to 4, on the day '
              'shown. An area you did not look at stays unmarked — it is not a '
              'zero, and every reading of this record says how many areas were '
              'rated.',
              style:
                  TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
            ),
            if (log.error case final error?) ...[
              const SizedBox(height: 10),
              Text(
                error,
                style: TextStyle(color: t.accent, fontSize: 12.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: log.canWrite ? _pickDay : null,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(dayLabel(day, inYear: log.today.year)),
            ),
            const SizedBox(height: 8),
            for (final area in MfgArea.ordered)
              _AreaRow(
                // A key per area so the tests can tap *this* row's chips: nine
                // rows of five identical digits is not something a text finder
                // can tell apart, and a tap on the wrong row would record a
                // rating against the wrong body part without failing anything.
                key: ValueKey('mfg-${area.id}'),
                area: area,
                value: _ratings[area],
                enabled: log.canWrite,
                onRate: (value) => _rate(area, value),
              ),
            const SizedBox(height: 4),
            if (problem != null)
              Text(
                problem,
                style:
                    TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.4),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: log.canWrite && problem == null ? _save : null,
                child: const Text('Save this check'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              mfgRefusalSheet,
              style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// One area: its title with the chosen word spelled out, and the five values.
class _AreaRow extends StatelessWidget {
  const _AreaRow({
    super.key,
    required this.area,
    required this.value,
    required this.enabled,
    required this.onRate,
  });

  final MfgArea area;
  final int? value;
  final bool enabled;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final word = value == null ? null : mfgWord(value!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            word == null ? area.title : '${area.title} · $word',
            style: TextStyle(
              color: word == null ? t.textSecondary : t.textPrimary,
              fontSize: 13,
              fontWeight: word == null ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var candidate = mfgMinValue;
                  candidate <= mfgMaxValue;
                  candidate++)
                Tooltip(
                  message: mfgWord(candidate) ?? '',
                  child: SizedBox(
                    width: 44,
                    height: 34,
                    child: Material(
                      color: value == candidate ? t.accent : t.surface,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSmall),
                      child: InkWell(
                        onTap: enabled ? () => onRate(candidate) : null,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSmall),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSmall),
                            border: Border.all(
                              color: value == candidate ? t.accent : t.border,
                              width: 1.3,
                            ),
                          ),
                          child: Text(
                            '$candidate',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: value == candidate
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: value == candidate
                                  ? t.onAccent
                                  : (enabled ? t.textSecondary : t.textFaint),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
