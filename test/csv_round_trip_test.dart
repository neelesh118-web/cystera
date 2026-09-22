// Export → parse → import → compare: the raw-record CSV fed back through the
// tracker parser, and the record that comes out the other side.
//
// The two ends of this loop were written for opposite directions — the export
// leaves the phone to be counted in a spreadsheet, the parser brings a history
// in from another tracker — so feeding one into the other is the strongest
// claim available about both: that the same facts survive being written down
// and read back. It also pins the parser to the export's own shape instead of
// a shape the test translates on its behalf.
//
// The loop has edges, and the test names them rather than hiding them:
//
//  * The tracker import carries what a tracker history is made of: cycle days
//    and symptoms. Notes, medicines, the "nothing today" flag and lab results
//    are export-only rows — they must come back as *counted skips*, not as
//    mangled days, and each boundary is asserted below.
//  * `backfilled` provenance has no column in the export, so every imported
//    mark reads as entered after the fact. That is the one difference from the
//    original record, asserted as the difference it is.

import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/import/tracker_csv.dart';
import 'package:cystera/core/labs/lab_models.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_controller.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:cystera/core/metrics/metric_models.dart';
import 'package:cystera/core/report/csv_export.dart';
import 'package:cystera/core/report/doctor_report.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime today = DateTime(2026, 9, 22);

/// The cycle/symptom rows of a raw-record CSV — the facts the tracker import
/// can carry, isolated for comparison. Sorted, because two exports iterate
/// insertion orders that need not agree, and a fact has no order.
List<String> carriable(String csv) {
  final rows = [
    for (final line in csv.split('\n'))
      if (line.startsWith('cycle,') || line.startsWith('symptom,')) line,
  ];
  return rows..sort();
}

/// Builds the export from whatever a repository currently holds.
Future<String> exportFrom(FakeLogRepository repository) async {
  final days = (await repository.loadRange(DateTime(2026, 6, 1), today))
      .values
      .toList();
  return buildCsv(ReportInput(
    today: today,
    days: days,
    marks: const [],
    medications: const [],
    settings: const CycleSettings(),
    metrics: MetricPrefs.none,
    labs: [
      LabResult(
        id: 'lab_1',
        analyteId: 'hba1c',
        label: 'HbA1c',
        day: DateTime(2026, 7, 1),
        value: 5.4,
        unit: '%',
      ),
    ],
  ));
}

void main() {
  late TestAppLock lock;

  setUp(() async {
    lock = await TestAppLock.create();
  });

  tearDown(() => lock.dispose());

  test('the raw-record CSV survives export → tracker parse → import', () async {
    // --- A record with everything the loop claims to carry, plus rows it
    // must refuse to carry rather than mangle.
    final source = FakeLogRepository();
    await source.markCycleDays(
      [DateTime(2026, 8, 3)],
      flow: FlowLevel.medium,
      backfilled: false,
    );
    await source.markCycleDays(
      [DateTime(2026, 8, 4), DateTime(2026, 8, 5)],
      flow: FlowLevel.light,
      backfilled: false,
    );
    await source.markCycleDays(
      [DateTime(2026, 8, 6)],
      flow: FlowLevel.heavy,
      backfilled: false,
    );
    await source.markCycleDays(
      [DateTime(2026, 8, 20)],
      kind: CycleMarkKind.spotting,
      backfilled: true,
    );
    await source.setSeverity(DateTime(2026, 8, 3), 'acne', Severity.severe);
    await source.setSeverity(DateTime(2026, 8, 3), 'bloating', Severity.moderate);
    await source.setSeverity(DateTime(2026, 8, 5), 'low_mood', Severity.mild);
    await source.setSeverity(DateTime(2026, 9, 5), 'anxiety', Severity.severe);
    // Export-only facts: each must be counted as a skip, not written anywhere.
    await source.setNote(DateTime(2026, 8, 4), 'Doctor appointment');
    await source.setNothing(DateTime(2026, 8, 15), true);
    await source.setMedTake(DateTime(2026, 8, 6), 'med_1', MedTake.taken);

    final firstExport = await exportFrom(source);

    // --- Through the parser: the same file a person could paste.
    final parse = parseTrackerCsv(firstExport, today: today);
    expect(parse.refusal, isNull);
    expect(parse.proposals, isNotEmpty);
    // Every line was either read as a day or counted as skipped — the summary
    // line on the review screen promises exactly this arithmetic.
    expect(parse.linesRead, parse.proposals.length + parse.linesSkipped);
    // No concern should fire on this file: its dates are ISO, in the past, one
    // row per fact.
    expect(
      parse.proposals.where((p) => p.needsReview),
      isEmpty,
      reason: parse.proposals
          .where((p) => p.needsReview)
          .map((p) => '${p.rawLine}: ${p.concerns}')
          .join('; '),
    );

    // --- Into a fresh record, through the real write path.
    final target = FakeLogRepository();
    final controller = LogController(
      repositoryOf: () => target,
      lock: lock.controller,
      clock: () => today,
    );
    addTearDown(controller.dispose);
    final outcome = await controller.importTrackerRows(parse.proposals);
    expect(outcome.left, isEmpty, reason: '${outcome.left}');

    // --- Every fact the export carried, back and identical.
    final sourceRange = await source.loadRange(DateTime(2026, 6, 1), today);
    final targetRange = await target.loadRange(DateTime(2026, 6, 1), today);

    for (final entry in sourceRange.entries) {
      final original = entry.value;
      final mark = original.cycleMark;
      final restored = targetRange[entry.key];

      if (mark == null && original.entries.isEmpty) {
        // The day's only facts were export-only (the "nothing" day), so
        // nothing at all may cross over: the day stays absent, which is what
        // "nothing recorded" means at this level of the record.
        expect(restored, isNull,
            reason: '${entry.key}: a day of export-only facts came across');
        continue;
      }

      expect(restored, isNotNull, reason: '${entry.key} missing from target');
      if (mark != null) {
        expect(restored!.cycleMark, isNotNull, reason: entry.key);
        expect(restored.cycleMark!.kind, mark.kind, reason: entry.key);
        expect(restored.cycleMark!.flow, mark.flow, reason: entry.key);
      } else {
        expect(restored!.cycleMark, isNull, reason: entry.key);
      }
      expect(restored.entries, original.entries, reason: entry.key);

      // The boundary, on every carried day: export-only facts never cross
      // over — not the note beside a period day, not the medicine taken on
      // one, not a "nothing" flag.
      expect(restored.nothing, isFalse, reason: entry.key);
      expect(restored.note, isNull, reason: entry.key);
      expect(restored.meds, isEmpty, reason: entry.key);
    }

    // And the same comparison as the export itself: re-exporting the restored
    // record produces the same cycle and symptom rows, byte for byte.
    final secondExport = await exportFrom(target);
    expect(carriable(secondExport), carriable(firstExport));
    expect(carriable(firstExport), isNotEmpty);

    // --- The one difference, by name: the export has no column for
    // provenance, so an imported day is always entered after the fact — even
    // the one that was logged live in the original record.
    final liveOriginal = sourceRange[DayKey.of(DateTime(2026, 8, 3))]!;
    expect(liveOriginal.cycleMark!.backfilled, isFalse);
    final restoredMark =
        (await target.loadDay(DateTime(2026, 8, 3))).cycleMark!;
    expect(restoredMark.backfilled, isTrue);

    // --- Spot checks that pin specific values, so a bug symmetric across
    // both exports cannot hide behind the comparison above.
    final august = await target.loadDay(DateTime(2026, 8, 3));
    expect(august.cycleMark!.kind, CycleMarkKind.period);
    expect(august.cycleMark!.flow, FlowLevel.medium);
    expect(august.entries['acne']!.level, 3);
    expect(august.entries['bloating']!.level, 2);

    final spotting = await target.loadDay(DateTime(2026, 8, 20));
    expect(spotting.cycleMark!.kind, CycleMarkKind.spotting);
    expect(spotting.cycleMark!.flow, isNull);

    final symptomOnly = await target.loadDay(DateTime(2026, 9, 5));
    expect(symptomOnly.cycleMark, isNull);
    expect(symptomOnly.entries['anxiety']!.level, 3);

    // The skipped rows landed nowhere, as counted.
    final nothingDay = await target.loadDay(DateTime(2026, 8, 15));
    expect(nothingDay.nothing, isFalse);
    final medDay = await target.loadDay(DateTime(2026, 8, 6));
    expect(medDay.meds, isEmpty);
    expect(medDay.cycleMark!.flow, FlowLevel.heavy, reason: 'the med row beside this day was skipped; the cycle row was not');
    final noteDay = await target.loadDay(DateTime(2026, 8, 4));
    expect(noteDay.note, isNull);
    expect(noteDay.cycleMark!.flow, FlowLevel.light);
    expect(
      await target.loadDay(DateTime(2026, 7, 1)),
      // The lab row parsed its date and was then counted as skipped: no mark,
      // no symptom, nothing invented on the draw date.
      isA<DayLog>()
          .having((d) => d.cycleMark, 'cycleMark', isNull)
          .having((d) => d.entries, 'entries', isEmpty),
    );
  });
}
