import 'package:flutter/material.dart';

import '../../core/labs/lab_controller.dart';
import '../../core/labs/lab_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import 'lab_import_sheet.dart';

/// The blood tests the user entered, and what the app will and will not say about
/// them.
///
/// The card is built around one refusal: **the app ships no reference range and no
/// unit.** Every number here is beside the range *the report printed*, quoted
/// verbatim, and the app's only arithmetic is to say where the value sits relative
/// to that. It never calls a result normal, never calls one abnormal, and never
/// converts a unit — a result in a second unit starts a second series, and the card
/// says why rather than drawing a line through two different scales.
class LabSection extends StatelessWidget {
  const LabSection({super.key, required this.labs, this.minimumPoints = 3});

  final LabController labs;

  /// How many readings in one unit it takes before a line is drawn. Three, not the
  /// five the daily measurements use: a blood test is a few times a year, so a
  /// higher floor would mean a line that almost never appears.
  final int minimumPoints;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final histories = labs.histories;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
              Icon(Icons.science_outlined, size: 18, color: t.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your blood tests',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Numbers you type off a printout, with the unit and the range exactly '
            'as the lab wrote them. The app has no ranges of its own — it does not '
            'know what a result means for you, and it will not guess.',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
          ),
          if (labs.error case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: t.accent, fontSize: 12.5, height: 1.4),
            ),
          ],
          if (!labs.loaded && labs.loading) ...[
            const SizedBox(height: 14),
            Text(
              'Reading your results…',
              style: TextStyle(color: t.textSecondary, fontSize: 12.5),
            ),
          ] else if (histories.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Nothing recorded yet. Add a result when a letter arrives and it '
              'will be kept here, in order, with the range from that report.',
              style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
            ),
          ] else
            for (final history in histories) ...[
              const SizedBox(height: 16),
              _HistoryBlock(
                history: history,
                minimumPoints: minimumPoints,
                labs: labs,
              ),
            ],
          const SizedBox(height: 12),
          // A `Wrap` rather than a `Row` with a `Spacer`, for the reason the
          // medication card gives: both labels announce themselves in full, and on
          // a 360pt phone at a slightly enlarged text scale they do not fit on one
          // line. A row would clip whichever came second.
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed:
                    labs.canWrite ? () => showLabEntrySheet(context, labs) : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add a result'),
              ),
              TextButton.icon(
                onPressed:
                    labs.canWrite ? () => showLabImportSheet(context, labs) : null,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste a report'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One analyte: its latest value against the printed range, and its line if there
/// are enough readings in one unit to draw one.
class _HistoryBlock extends StatelessWidget {
  const _HistoryBlock({
    required this.history,
    required this.minimumPoints,
    required this.labs,
  });

  final LabHistory history;
  final int minimumPoints;
  final LabController labs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final series = history.series;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          history.label,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final (index, one) in series.indexed) ...[
          _SeriesRow(
            series: one,
            minimumPoints: minimumPoints,
            showUnitHeading: series.length > 1,
            // Only the newest result in the newest unit is editable from the
            // card. An older draw is reached through its own series, which is the
            // one place the unit it was reported in is unambiguous.
            onEdit: index == 0 && labs.canWrite
                ? () => showLabEntrySheet(context, labs, existing: one.latest)
                : null,
          ),
          if (one != series.last) const SizedBox(height: 10),
        ],
        if (history.hasMixedUnits) ...[
          const SizedBox(height: 8),
          Text(
            'These were reported in more than one unit, so they are kept apart '
            'rather than drawn as one line. The app does not convert between '
            'units: a conversion is another lab-specific number, and getting it '
            'wrong here would move every point on the chart.',
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// One unit's worth of a history: the latest reading, its printed range, where it
/// sits, and the line if there is enough of it.
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({
    required this.series,
    required this.minimumPoints,
    required this.showUnitHeading,
    this.onEdit,
  });

  final LabSeries series;
  final int minimumPoints;
  final bool showUnitHeading;

  /// Opens the editor on the newest result in this series, or null when the row
  /// has no editable head — an older unit, or a locked record.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final latest = series.latest;
    final rangeText = series.rangeText;
    final position = series.latestPosition;
    final sentence = positionSentence(position);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showUnitHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              latest.unit.isEmpty ? 'No unit given' : latest.unit,
              style: TextStyle(
                color: t.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              latest.valueAndUnit,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                dayLabel(latest.day, inYear: DateTime.now().year),
                style: TextStyle(color: t.textFaint, fontSize: 12),
              ),
            ),
            if (onEdit != null)
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Edit', style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          rangeText == null
              ? 'No range recorded for this one.'
              : 'Lab range: $rangeText${latest.unit.isEmpty ? '' : ' ${latest.unit}'}',
          style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.4),
        ),
        if (sentence.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            sentence,
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.4),
          ),
        ],
        if (series.count >= 2) ...[
          const SizedBox(height: 4),
          Text(
            _summary(series),
            style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.45),
          ),
        ],
        if (series.count >= minimumPoints) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: CustomPaint(
              painter: _LabLinePainter(
                values: [for (final point in series.points) point.value],
                days: [for (final point in series.points) point.day],
                line: t.textSecondary,
                faint: t.border,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ] else if (series.count >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${series.count} readings, so no line yet — $minimumPoints is the '
              'floor, because a shape drawn from two points is a straight line '
              'dressed up as a trend.',
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            ),
          ),
        if (latest.note case final note?) ...[
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }
}

String _summary(LabSeries series) {
  final unitWord = series.unit.isEmpty ? '' : ' ${series.unit}';
  final parts = [
    '${series.count} readings',
    'lowest ${_num(series.lowest)}$unitWord',
    'highest ${_num(series.highest)}$unitWord',
  ];
  if (series.change case final change?) {
    final sign = change > 0 ? '+' : (change < 0 ? '−' : '');
    parts.add(
      'from ${_num(series.earliest.value)} to ${_num(series.latest.value)} '
      '($sign${_num(change.abs())}$unitWord)',
    );
  }
  return '${parts.join(', ')}.';
}

String _num(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  var text = value.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.replaceFirst(RegExp(r'\.$'), '');
}

/// A plain polyline over the reading days. No range band and no target line: both
/// would require the app to draw its own idea of what the number should be.
class _LabLinePainter extends CustomPainter {
  _LabLinePainter({
    required this.values,
    required this.days,
    required this.line,
    required this.faint,
  });

  final List<double> values;
  final List<DateTime> days;
  final Color line;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final firstDay = days.first;
    final lastDay = days.last;
    final totalDays = lastDay.difference(firstDay).inDays;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final span = (high - low).abs() < 0.0001 ? null : high - low;

    double x(int index) {
      if (totalDays <= 0) return size.width / 2;
      return days[index].difference(firstDay).inDays / totalDays * size.width;
    }

    double y(double value) {
      if (span == null) return size.height / 2;
      const inset = 4.0;
      final usable = size.height - inset * 2;
      return inset + (high - value) / span * usable;
    }

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = faint
        ..strokeWidth = 1,
    );

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(x(i), y(values[i]));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );

    final dot = Paint()..color = line;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(x(i), y(values[i])), 2.6, dot);
    }
  }

  @override
  bool shouldRepaint(_LabLinePainter old) =>
      old.values != values || old.days != days || old.line != line;
}

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

/// Adds a result, or edits one already on record.
///
/// The unit and the range are plain text fields with no suggestions and no
/// validation, because the report is the authority: a picker of "common units"
/// would be the app telling the user what their lab meant, and it would be wrong
/// for the next country. The value field is the only one parsed, and it refuses a
/// non-number with a sentence rather than the word "invalid".
Future<void> showLabEntrySheet(
  BuildContext context,
  LabController labs, {
  LabResult? existing,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
      ),
      builder: (_) => _LabEntrySheet(labs: labs, existing: existing),
    );

class _LabEntrySheet extends StatefulWidget {
  const _LabEntrySheet({required this.labs, this.existing});

  final LabController labs;
  final LabResult? existing;

  @override
  State<_LabEntrySheet> createState() => _LabEntrySheetState();
}

class _LabEntrySheetState extends State<_LabEntrySheet> {
  static const String _otherId = '__other__';

  late String _selected = _initialSelection();
  late final TextEditingController _customLabel =
      TextEditingController(text: _initialCustomLabel());
  late final TextEditingController _value =
      TextEditingController(text: widget.existing == null ? '' : _num(widget.existing!.value));
  late final TextEditingController _unit =
      TextEditingController(text: widget.existing?.unit ?? '');
  late final TextEditingController _range =
      TextEditingController(text: widget.existing?.rangeText ?? '');
  late final TextEditingController _lab =
      TextEditingController(text: widget.existing?.labName ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _day = widget.existing?.day ?? widget.labs.defaultDay;
  String? _problem;

  String _initialSelection() {
    final existing = widget.existing;
    if (existing == null) return LabCatalogue.all.first.id;
    if (existing.analyteId case final id?) return id;
    return _otherId;
  }

  String _initialCustomLabel() {
    final existing = widget.existing;
    if (existing == null || existing.analyteId != null) return '';
    return existing.label;
  }

  @override
  void dispose() {
    _customLabel.dispose();
    _value.dispose();
    _unit.dispose();
    _range.dispose();
    _lab.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _editing => widget.existing != null;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final custom = _selected == _otherId;
    final selectedAnalyte = LabCatalogue.byId(_selected);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _editing ? 'Edit this result' : 'Add a result',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Copy the number, the unit and the range exactly as your report '
              'prints them. The app keeps your lab\'s wording rather than its own, '
              'so a card here and a letter on paper say the same thing.',
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            Text('Which test', style: TextStyle(color: t.textFaint, fontSize: 12.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final analyte in LabCatalogue.all)
                  ChoiceChip(
                    label: Text(analyte.title),
                    selected: _selected == analyte.id,
                    onSelected: (_) => setState(() => _selected = analyte.id),
                  ),
                ChoiceChip(
                  label: const Text('Something else'),
                  selected: custom,
                  onSelected: (_) => setState(() => _selected = _otherId),
                ),
              ],
            ),
            if (selectedAnalyte != null) ...[
              const SizedBox(height: 8),
              Text(
                selectedAnalyte.alsoPrintedAs.isEmpty
                    ? selectedAnalyte.blurb
                    : '${selectedAnalyte.blurb} Also printed as: '
                        '${selectedAnalyte.alsoPrintedAs.join(', ')}.',
                style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
              ),
            ],
            if (custom) ...[
              const SizedBox(height: 12),
              _Field(
                controller: _customLabel,
                label: 'What your report calls it',
                hint: 'e.g. FSH, Vitamin D, Prolactin',
              ),
            ],
            const SizedBox(height: 12),
            _Field(
              controller: _value,
              label: 'The number',
              hint: 'e.g. 2.4',
              numeric: true,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _unit,
              label: 'Unit, exactly as printed',
              hint: 'e.g. ng/mL, nmol/L, %, mIU/L',
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _range,
              label: 'Range, exactly as printed (optional)',
              hint: 'e.g. 0.5–4.5, or < 5.0',
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDay,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 18, color: t.textFaint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sample date: '
                        '${dayLabel(_day, inYear: DateTime.now().year)}',
                        style: TextStyle(color: t.textPrimary, fontSize: 14),
                      ),
                    ),
                    Text('Change', style: TextStyle(color: t.accent, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The day the sample was taken, not the day you type it in. A result '
              'that arrived weeks later belongs where it was drawn.',
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _lab,
              label: 'Lab or clinic (optional)',
              hint: 'e.g. the name on the letterhead',
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _note,
              label: 'Note (optional)',
              hint: 'e.g. day 3 of my cycle, or after 12 hours fasting',
            ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 10),
              Text(
                problem,
                style: TextStyle(
                  color: t.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(_editing ? 'Save changes' : 'Save this result'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (_editing) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: _remove,
                style: TextButton.styleFrom(foregroundColor: t.accent),
                child: const Text('Remove this result'),
              ),
              Text(
                'A typed-in number with a wrong digit is a slip, not a history, so '
                'this removes it from the record rather than hiding it.',
                style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      // A sample cannot be drawn in the future. A minute of slack covers a clock
      // a few seconds ahead rather than a real future date.
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _save() async {
    final custom = _selected == _otherId;
    if (custom && _customLabel.text.trim().isEmpty) {
      setState(() => _problem = 'Give this result a name — the one on the report.');
      return;
    }
    switch (parseLabValue(_value.text)) {
      case LabRejected(:final reason):
        setState(() => _problem = reason);
        return;
      case LabAccepted(:final value):
        final navigator = Navigator.of(context);
        final saved = await widget.labs.save(
          id: widget.existing?.id,
          analyteId: custom ? null : _selected,
          label: custom ? _customLabel.text : null,
          day: _day,
          value: value,
          unit: _unit.text.trim(),
          rangeText: _range.text,
          labName: _lab.text,
          note: _note.text,
        );
        if (!mounted) return;
        if (!saved) {
          setState(() => _problem = widget.labs.error ?? 'That did not save.');
          return;
        }
        navigator.pop();
    }
  }

  Future<void> _remove() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final navigator = Navigator.of(context);
    await widget.labs.remove(id);
    if (!mounted) return;
    navigator.pop();
  }
}

/// One labelled text field, styled like the rest of the app's sheets.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.numeric = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: t.textFaint, fontSize: 12.5)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: TextStyle(color: t.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: t.textFaint, fontSize: 14),
            filled: true,
            fillColor: t.background,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide(color: t.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide(color: t.border),
            ),
          ),
        ),
      ],
    );
  }
}
