import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/log/day_key.dart';
import '../../core/log/log_controller.dart';
import '../../core/log/log_models.dart';
import '../../core/log/severity.dart';
import '../../core/theme/app_theme.dart';
import 'severity_ramp.dart';

/// Records a period that was not logged while it was happening.
///
/// This is the honest version of a feature every cycle app has and few admit to:
/// most first-week data is entered after the fact, from memory, in a burst. The
/// screen says so instead of pretending the dates were observed live, and the
/// flag travels with the rows into the database and into the doctor report.
///
/// [pickDate] is injectable so the sheet can be tested without driving a Material
/// date picker, which is a test of Flutter rather than of this screen.
class BackfillSheet extends StatefulWidget {
  const BackfillSheet({
    super.key,
    required this.log,
    this.today,
    this.pickDate,
  });

  final LogController log;

  final DateTime? today;

  final Future<DateTime?> Function(BuildContext context, DateTime initial)? pickDate;

  @override
  State<BackfillSheet> createState() => _BackfillSheetState();
}

class _BackfillSheetState extends State<BackfillSheet> {
  late DateTime _today;
  late DateTime _start;
  late DateTime _end;
  FlowLevel? _flow;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _today = DayKey.dayOf(widget.today ?? DateTime.now());
    // Defaults to the last five days ending yesterday: the common case is a
    // period that has just finished, and five days is a typical length. Both
    // ends are one tap away, and a wrong default shows its dates in full rather
    // than hiding them behind "recent".
    _end = DayKey.addDays(_today, -1);
    _start = DayKey.addDays(_end, -4);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final request = BackfillRequest(start: _start, end: _end, today: _today);
    final validation = request.validate();
    final days = validation is BackfillAccepted ? validation.days : const <DateTime>[];
    final rejection = validation is BackfillRejected ? validation.reason : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.gutter,
        4,
        AppTheme.gutter,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Record a past period', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Entered from memory, so it is kept as a period you added later rather than one you '
            'logged at the time. Your record will show which is which.',
            style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'First day',
                  date: _start,
                  onTap: () => _pick(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  label: 'Last day',
                  date: _end,
                  onTap: () => _pick(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'How heavy was it? Optional — skip it if you do not remember.',
            style: TextStyle(color: t.textFaint, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          SeverityRamp(
            value: _flow,
            semanticLabel: 'Flow',
            levels: FlowLevel.values,
            // Tapping the level already chosen clears it, same as everywhere else.
            onChanged: (level) => setState(
              () => _flow = _flow == level ? null : level as FlowLevel,
            ),
          ),
          const SizedBox(height: 16),
          if (rejection != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: t.accentSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rejection,
                      style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (days.isNotEmpty)
            Text(
              days.length == 1
                  ? '1 day will be recorded as a period.'
                  : '${days.length} days will be recorded as a period.',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: rejection != null || _saving ? null : () => _save(request, days),
            child: Text(_saving ? 'Saving…' : 'Record these days'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _message!,
                style: TextStyle(color: t.textSecondary, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pick({required bool isStart}) async {
    // The range is kept legal by construction: picking a start after the end
    // would otherwise produce a rejection sentence for something the user did
    // not do wrong.
    final picked = await (widget.pickDate ?? _defaultPicker)(
      context,
      isStart ? _start : _end,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = DayKey.dayOf(picked);
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = DayKey.dayOf(picked);
        if (_start.isAfter(_end)) _start = _end;
      }
    });
  }

  static Future<DateTime?> _defaultPicker(BuildContext context, DateTime initial) {
    final today = DayKey.dayOf(DateTime.now());
    return showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      // Two years back is the same limit the validation applies, so the picker
      // cannot offer a date the sheet will then refuse.
      firstDate: DayKey.addDays(today, -BackfillRequest.maxPastDays),
      lastDate: today,
      helpText: 'Pick a day',
    );
  }

  Future<void> _save(BackfillRequest request, List<DateTime> days) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    final outcome = await widget.log.backfillPeriod(request, flow: _flow);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = outcome.message;
    });
    // The sheet closes on success and stays open with the reason on failure, so
    // a refusal cannot be mistaken for a save. The outcome says which happened;
    // the sentence is for the user, not for this decision.
    if (outcome.saved) Navigator.of(context).pop();
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: t.textFaint, fontSize: 11.5)),
              const SizedBox(height: 3),
              Text(
                '${date.day} ${_monthName(date.month)} ${date.year}',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthName(int month) => const [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][month];
}

/// Opens the sheet with the app's real dependencies.
Future<void> showBackfillSheet(BuildContext context) {
  final log = context.read<LogController>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // `today` comes from the controller rather than from the sheet's own clock,
    // so the default range and the rest of the screen cannot disagree about what
    // day it is — near midnight, or under a test's fixed clock, they would.
    builder: (_) => BackfillSheet(log: log, today: log.today),
  );
}
