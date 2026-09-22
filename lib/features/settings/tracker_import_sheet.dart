import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/import/tracker_csv.dart';
import '../../core/log/log_controller.dart';
import '../../core/log/log_models.dart';
import '../../core/log/severity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';

/// Paste or pick another tracker's CSV, look at what the app thinks each line
/// means, and only then decide what enters the record.
///
/// This is the labs paste path's contract, kept: two stages, every proposal
/// shown **beside the line it came from** when anything about it was uncertain,
/// the concerns written out in sentences, a row whose *day* the parse could not
/// settle starting unticked, and nothing written until a row is ticked and the
/// button pressed. The differences are scale (a history is hundreds of rows, so
/// the rows scroll between a pinned header and footer) and one extra control:
/// flow and severity chips, because a tracker records that a symptom happened
/// and never how bad it was — that default is on the row, stated, editable.
Future<void> showTrackerImportSheet(BuildContext context, LogController log) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
      ),
      builder: (_) => TrackerImportSheet(log: log),
    );

/// The sheet, public so a test can pump it without going through the modal.
class TrackerImportSheet extends StatefulWidget {
  const TrackerImportSheet({super.key, required this.log});

  final LogController log;

  @override
  State<TrackerImportSheet> createState() => _TrackerImportSheetState();
}

class _TrackerImportSheetState extends State<TrackerImportSheet> {
  final TextEditingController _text = TextEditingController();

  /// Null until "Find the days" has been pressed: the review stage does not
  /// exist before there is something to review.
  TrackerImportParse? _parse;
  List<_Draft>? _drafts;

  /// What the sheet says after the button is pressed, so the person is told how
  /// many days went in and which were left, rather than the sheet closing on
  /// them. Same reason the labs sheet holds one.
  TrackerImportOutcome? _outcome;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final parse = _parse;
    final body = parse == null
        ? _pasteStage(t)
        : _outcome != null || parse.isEmpty
            ? _simpleStage(t)
            : _reviewStage(t);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: body,
    );
  }

  // -------------------------------------------------------------------------
  // Stage one: the text.
  // -------------------------------------------------------------------------

  Widget _pasteStage(AppTokens t) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bring your history from another tracker',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Export the CSV from Flo or wherever you kept your history, and '
              'paste it below or choose the file. The app reads it on this '
              'phone, shows what it thinks each line means, and asks you to '
              'check it — nothing enters your record until you tick a row and '
              'press add.',
              style:
                  TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              maxLines: 6,
              minLines: 4,
              // The button below is enabled from the field's contents, so the
              // sheet has to rebuild as they change — the labs sheet's comment
              // applies word for word here.
              onChanged: (_) => setState(() {}),
              style:
                  TextStyle(color: t.textPrimary, fontSize: 13.5, height: 1.4),
              decoration: InputDecoration(
                hintText:
                    'Date,Period,Flow,Symptoms\n2026-08-03,YES,Medium,"Bloating, Low mood"',
                hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
                filled: true,
                fillColor: t.background,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
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
                TextButton.icon(
                  onPressed: _chooseFile,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Choose a file'),
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
                    onPressed:
                        _text.text.trim().isEmpty ? null : _read,
                    child: const Text('Find the days'),
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
              'Everything here is read on the phone. There is no upload, and '
              'the app has no internet permission to upload anything with.',
              style:
                  TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            ),
          ],
        ),
      );

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

  /// The file is only another way to get text into the field above: one parse
  /// path, one review stage, whatever the bytes came through.
  Future<void> _chooseFile() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose the CSV file',
      type: FileType.any,
    );
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    setState(() {
      _text.text = decodeCsvBytes(bytes);
    });
  }

  void _read() {
    final parse = parseTrackerCsv(_text.text, today: widget.log.today);
    setState(() {
      _parse = parse;
      _drafts = [for (final proposal in parse.proposals) _Draft(proposal)];
      _outcome = null;
    });
  }

  // -------------------------------------------------------------------------
  // Stage two: what it read.
  // -------------------------------------------------------------------------

  /// The outcome and the refusal screens: short, so they scroll the labs way.
  Widget _simpleStage(AppTokens t) {
    final parse = _parse!;
    final outcome = _outcome;

    if (outcome != null) {
      final year = widget.log.today.year;
      final added = <String>[
        if (outcome.daysMarked > 0)
          '${outcome.daysMarked} period ${outcome.daysMarked == 1 ? 'day' : 'days'}',
        if (outcome.symptomsWritten > 0)
          '${outcome.symptomsWritten} symptom '
              '${outcome.symptomsWritten == 1 ? 'entry' : 'entries'}',
      ];
      final shownLeft = outcome.left.take(6).toList();
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Done', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              outcome.addedAnything
                  ? '${added.join(' and ')} added to your record.'
                  : 'Nothing was added.',
              style:
                  TextStyle(color: t.textPrimary, fontSize: 13.5, height: 1.5),
            ),
            if (outcome.left.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Left out, because the record already says otherwise or the '
                'line held nothing to add: '
                '${[
                  for (final entry in shownLeft)
                    '${dayLabel(entry.day, inYear: year)} — ${entry.reason}',
                ].join('; ')}'
                '${outcome.left.length > shownLeft.length ? '; and ${outcome.left.length - shownLeft.length} more' : ''}.',
                style: TextStyle(
                    color: t.textSecondary, fontSize: 12.5, height: 1.5),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    if (parse.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nothing read', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              parse.refusal ??
                  'Not one of these lines held a date this could read. Check '
                      'the file is the CSV another tracker exported.',
              style:
                  TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
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
          ],
        ),
      );
    }

    // Unreachable: the build picks _reviewStage when the parse is non-empty and
    // there is no outcome. Kept so the type system does not have to be told.
    return const SizedBox.shrink();
  }

  /// The rows, between a pinned summary and a pinned add button — a history can
  /// be hundreds of rows, so unlike the labs sheet the list owns its scroll.
  Widget _reviewStage(AppTokens t) {
    final parse = _parse!;
    final drafts = _drafts!;
    final saveable = _saveable(drafts);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Check what was read',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${parse.linesRead} ${parse.linesRead == 1 ? 'line' : 'lines'} '
            'read, ${drafts.length} looked like '
            '${drafts.length == 1 ? 'a day' : 'days'}'
            '${parse.linesSkipped > 0 ? ', ${parse.linesSkipped} held nothing this app records' : ''}, '
            '${parse.needsReview} to check.',
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Symptom rows start at Mild — the file records that a symptom '
            'happened, not how bad it was — so change any before you add. '
            'Period days go in marked as entered after the fact.',
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: drafts.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Row(
                key: ValueKey('tracker-row-$index'),
                draft: drafts[index],
                year: widget.log.today.year,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: saveable.isEmpty ? null : _save,
                child: Text(
                  'Add ${saveable.length} '
                  '${saveable.length == 1 ? 'day' : 'days'}',
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() {
                _parse = null;
                _drafts = null;
              }),
              child: const Text('Paste again'),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  /// The rows that would be written right now: ticked and able to write.
  List<_Draft> _saveable(List<_Draft> drafts) => [
        for (final draft in drafts)
          if (draft.checked && draft.proposal.canWrite) draft,
      ];

  Future<void> _save() async {
    final rows = [
      for (final draft in _saveable(_drafts!)) draft.proposal,
    ];
    if (rows.isEmpty) return;
    final outcome = await widget.log.importTrackerRows(rows);
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
    });
  }
}

/// One proposal: its line, its concerns, and the fields it will be written with.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.draft, required this.year, required this.onChanged});

  final _Draft draft;
  final int year;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final proposal = draft.proposal;
    final review = proposal.needsReview;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: review ? t.accentSoft : t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: draft.checked,
                // A row that cannot write (a future date) is not tickable: the
                // checkbox says no rather than accepting a tap it would ignore.
                onChanged: proposal.canWrite
                    ? (value) {
                        draft.checked = value ?? false;
                        onChanged();
                      }
                    : null,
              ),
              Expanded(
                child: Text(
                  review ? 'Check this one' : 'Read cleanly',
                  style: TextStyle(
                    color: review ? t.accent : t.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          // The line the row came from, shown where something was uncertain —
          // a row the person cannot check against its source is a row they have
          // to take on trust.
          if (review) ...[
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
                  proposal.sentenceFor(concern),
                  style:
                      TextStyle(color: t.accent, fontSize: 12, height: 1.4),
                ),
              ),
            const SizedBox(height: 6),
          ],
          Text(
            dayLabel(proposal.day, inYear: year),
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (proposal.markKind == CycleMarkKind.spotting)
            Text(
              'Spotting',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
          if (proposal.markKind == CycleMarkKind.period) ...[
            Text(
              'Period — how heavy:',
              style: TextStyle(color: t.textFaint, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final level in FlowLevel.values)
                  ChoiceChip(
                    label: Text(level.word),
                    selected: proposal.flow == level,
                    onSelected: (_) {
                      proposal.flow = level;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
          for (final symptom in proposal.symptoms) ...[
            const SizedBox(height: 6),
            // A Wrap rather than a row: three severity chips plus a label does
            // not fit a narrow phone on one line, and chips that overflow the
            // screen are chips nobody can tap.
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  symptom.label,
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                ),
                for (final severity in Severity.values)
                  ChoiceChip(
                    label: Text(severity.word),
                    selected: symptom.severity == severity,
                    onSelected: (_) {
                      symptom.severity = severity;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A draft row: the proposal it will write, and whether the person ticked it.
///
/// The editable values (flow, severity) live on the proposal itself — the parse
/// output is a draft by nature, and the review screen mutates it in place. The
/// record only ever sees these rows through `importTrackerRows`, after the tick.
class _Draft {
  _Draft(this.proposal) : checked = proposal.startsTicked;

  final TrackerProposal proposal;
  bool checked;
}
