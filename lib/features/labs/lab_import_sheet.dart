import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/labs/lab_controller.dart';
import '../../core/labs/lab_models.dart';
import '../../core/labs/report_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';

/// Paste the text of a report, look at what the app thinks it read, and only then
/// decide what goes in the record.
///
/// The two stages are the point. The first takes the pasted text; the second shows
/// every reading **beside the line it came from**, marks the ones the parse could
/// not settle and says what it could not settle, and writes nothing until a row is
/// ticked and the button pressed. A row whose value is uncertain starts *unticked*,
/// so "add everything" cannot silently include a number the app was unsure of.
///
/// There is no photograph here yet. Reading a picture needs an on-device OCR engine,
/// which is a third-party SDK and therefore a decision about the app's no-network
/// invariant — see `docs/labs.md`.
Future<void> showLabImportSheet(BuildContext context, LabController labs) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
      ),
      builder: (_) => LabImportSheet(labs: labs),
    );

/// The sheet, public so a test can pump it without going through the modal.
class LabImportSheet extends StatefulWidget {
  const LabImportSheet({super.key, required this.labs});

  final LabController labs;

  @override
  State<LabImportSheet> createState() => _LabImportSheetState();
}

class _LabImportSheetState extends State<LabImportSheet> {
  final TextEditingController _text = TextEditingController();

  /// Null until "Find results" has been pressed: the review stage does not exist
  /// before there is something to review.
  ReportParse? _parse;
  List<_Draft>? _drafts;

  DateTime _day = DateTime.now();

  /// What the sheet says after the button is pressed, so the user is told how many
  /// were added and which were left rather than the sheet simply closing on them.
  ({int added, List<String> left})? _outcome;

  @override
  void dispose() {
    _text.dispose();
    for (final draft in _drafts ?? const <_Draft>[]) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
          children: _parse == null ? _pasteStage(t) : _reviewStage(t),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Stage one: the text.
  // -------------------------------------------------------------------------

  List<Widget> _pasteStage(AppTokens t) => [
        Text(
          'Paste a report',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Copy the text from your results and paste it below. The app reads what '
          'it can, shows you what it thinks it found, and asks you to check it — '
          'nothing is added to your record until you say so.',
          style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          maxLines: 6,
          minLines: 4,
          // The button below is enabled from the field's contents, so the sheet
          // has to rebuild as they change. Without this it stayed disabled until
          // something else happened to rebuild it, which on a real screen means
          // the button appears dead after a paste.
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: t.textPrimary, fontSize: 13.5, height: 1.4),
          decoration: InputDecoration(
            hintText: 'HbA1c 5.4 % < 5.7\nFasting insulin 8.4 mIU/L < 25',
            hintStyle: TextStyle(color: t.textFaint, fontSize: 13),
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
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('Paste from clipboard'),
            ),
            TextButton(
              onPressed: () => setState(() => _text.clear()),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _text.text.trim().isEmpty ? null : _read,
                child: const Text('Find the results'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Everything here is read on the phone. There is no upload, and the app '
          'has no internet permission to upload anything with.',
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
      ];

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      setState(() {});
      return;
    }
    if (!mounted) return;
    setState(() {
      _text.text = text;
    });
  }

  void _read() {
    final parse = parseReportText(_text.text);
    setState(() {
      for (final draft in _drafts ?? const <_Draft>[]) {
        draft.dispose();
      }
      _parse = parse;
      _drafts = [for (final proposal in parse.proposals) _Draft(proposal)];
      // The date the report carries, applied *and* shown with the words it came
      // from. Filing an August draw under the day someone got round to pasting it
      // would move the point on the only axis this feature has, and the note under
      // the row says where the date came from and that it is worth a look.
      _day = parse.suggestedDate ?? DateTime.now();
    });
  }

  // -------------------------------------------------------------------------
  // Stage two: what it read.
  // -------------------------------------------------------------------------

  List<Widget> _reviewStage(AppTokens t) {
    final parse = _parse!;
    final drafts = _drafts!;
    final outcome = _outcome;

    if (outcome != null) {
      return [
        Text('Done', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          outcome.added == 1
              ? '1 result added to your record.'
              : '${outcome.added} results added to your record.',
          style: TextStyle(color: t.textPrimary, fontSize: 13.5, height: 1.5),
        ),
        if (outcome.left.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Not added, because they still need something from you: '
            '${outcome.left.join(', ')}.',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.5),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ];
    }

    if (parse.isEmpty) {
      return [
        Text('Nothing read', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${parse.linesRead} ${parse.linesRead == 1 ? 'line was' : 'lines were'} '
          'looked at and none of them looked like a result. A report copied out of '
          'a table sometimes comes through in a shape this cannot read — type the '
          'values in instead rather than trusting a guess.',
          style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() => _parse = null),
                child: const Text('Try another paste'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ];
    }

    return [
      Text('Check what was read', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        '${parse.linesRead} ${parse.linesRead == 1 ? 'line' : 'lines'} read, '
        '${drafts.length} looked like ${drafts.length == 1 ? 'a result' : 'results'}, '
        '${parse.needsReview} to check.',
        style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 12),
      _dateRow(t, parse),
      const SizedBox(height: 10),
      for (final draft in drafts) ...[
        _ProposalRow(
          draft: draft,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 10),
      ],
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _saveable(drafts).isEmpty ? null : _save,
              child: Text(
                'Add ${_saveable(drafts).length} '
                '${_saveable(drafts).length == 1 ? 'result' : 'results'}',
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() => _parse = null),
            child: const Text('Paste again'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Each row goes in exactly as you leave it, with your report\'s own wording '
        'for the unit and the range. Nothing is converted and nothing is judged.',
        style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
      ),
    ];
  }

  Widget _dateRow(AppTokens t, ReportParse parse) {
    final suggested = parse.suggestedDate;
    return InkWell(
      onTap: _pickDay,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_outlined, size: 18, color: t.textFaint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sample date: ${dayLabel(_day, inYear: DateTime.now().year)}',
                    style: TextStyle(color: t.textPrimary, fontSize: 14),
                  ),
                ),
                Text('Change', style: TextStyle(color: t.accent, fontSize: 13)),
              ],
            ),
            if (suggested != null && parse.suggestedDateText != null) ...[
              const SizedBox(height: 6),
              Text(
                'The report says "${parse.suggestedDateText}", so that is the date '
                'above. Check it — a date written 12/08 is the twelfth of August in '
                'most places and the eighth of December in others.',
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
      initialDate: _parse?.suggestedDate ?? _day,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  /// The rows that would be written right now: ticked, named and numbered.
  List<_Draft> _saveable(List<_Draft> drafts) => [
        for (final draft in drafts)
          if (draft.checked && _problem(draft) == null) draft,
      ];

  /// Why a row cannot be written yet, or null.
  static String? _problem(_Draft draft) {
    if (draft.name.text.trim().isEmpty) {
      return 'Needs the test\'s name from your report.';
    }
    return switch (parseLabValue(draft.value.text)) {
      LabRejected(:final reason) => reason,
      LabAccepted() => null,
    };
  }

  Future<void> _save() async {
    final drafts = _saveable(_drafts!);
    var added = 0;
    final left = <String>[];

    for (final draft in drafts) {
      final parsed = parseLabValue(draft.value.text) as LabAccepted;
      final saved = await widget.labs.save(
        // The name goes through the controller's synonym match, so an edited
        // "A1c" still lands on the HbA1c series rather than starting a new one.
        label: draft.name.text,
        day: _day,
        value: parsed.value,
        unit: draft.unit.text,
        rangeText: draft.range.text,
      );
      if (saved) {
        added += 1;
        draft.checked = false;
      } else {
        left.add(draft.name.text.trim());
      }
    }

    if (!mounted) return;
    setState(() {
      _outcome = (added: added, left: left);
    });
  }
}

/// One proposal, with its fields editable and its line on show.
class _ProposalRow extends StatelessWidget {
  const _ProposalRow({required this.draft, required this.onChanged});

  final _Draft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final proposal = draft.proposal;
    final problem = _LabImportSheetState._problem(draft);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: proposal.needsReview ? t.accentSoft : t.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: draft.checked,
                onChanged: problem != null
                    ? null
                    : (value) {
                        draft.checked = value ?? false;
                        onChanged();
                      },
              ),
              Expanded(
                child: Text(
                  proposal.needsReview ? 'Check this one' : 'Read cleanly',
                  style: TextStyle(
                    color: proposal.needsReview ? t.accent : t.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          if (proposal.needsReview) ...[
            // The line the reading came from. Shown only where something was
            // uncertain: a reading the user cannot check against the source is a
            // reading they have to take on trust.
            Text(
              proposal.rawLine,
              style: TextStyle(
                color: t.textFaint,
                fontSize: 11.5,
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            for (final concern in proposal.concerns)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  concernSentence(concern),
                  style: TextStyle(color: t.accent, fontSize: 12, height: 1.4),
                ),
              ),
            const SizedBox(height: 8),
          ],
          _Field(controller: draft.name, label: 'Test', onChanged: onChanged),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _Field(
                  controller: draft.value,
                  label: 'Result',
                  numeric: true,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _Field(controller: draft.unit, label: 'Unit', onChanged: onChanged),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Field(
            controller: draft.range,
            label: 'Range as printed (optional)',
            onChanged: onChanged,
          ),
          if (problem != null) ...[
            const SizedBox(height: 8),
            Text(
              problem,
              style: TextStyle(
                color: t.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A draft row: the proposal plus the fields the user can correct.
class _Draft {
  _Draft(this.proposal)
      : name = TextEditingController(text: proposal.label),
        value = TextEditingController(text: _trim(proposal.value)),
        unit = TextEditingController(text: proposal.unit),
        range = TextEditingController(text: proposal.rangeText ?? '') {
    // A row whose *value* was uncertain starts unticked, so "add everything" is
    // never a way to include a number the app was unsure of. A name borrowed from
    // the line above, or a missing range, is visible in the fields and is not a
    // reason to leave a good reading out.
    checked = !(proposal.concerns.contains(LabConcern.valueAmbiguous) ||
        proposal.concerns.contains(LabConcern.noName) ||
        proposal.concerns.contains(LabConcern.noUnit));
  }

  final LabProposal proposal;
  final TextEditingController name;
  final TextEditingController value;
  final TextEditingController unit;
  final TextEditingController range;
  bool checked = true;

  void dispose() {
    name.dispose();
    value.dispose();
    unit.dispose();
    range.dispose();
  }

  static String _trim(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    var text = value.toStringAsFixed(4);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    return text.replaceFirst(RegExp(r'\.$'), '');
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.numeric = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool numeric;

  /// Called as the text changes, so the row is re-evaluated: without it a row that
  /// needed a name stayed un-addable until some other tap happened to rebuild the
  /// sheet, which is the checkbox appearing broken.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: t.textFaint, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged == null ? null : (_) => onChanged!(),
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: TextStyle(color: t.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.background,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
