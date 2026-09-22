// The doctor report and the CSV export.
//
// Two things are defended here. First, that the report says the same thing the app
// says — including printing a refusal, so a report never makes the app look more
// confident than it is. Second, that the CSV never drops a fact to keep the file
// tidy: an unrecognised symptom id or an archived medication still gets its rows,
// because a spreadsheet that quietly omits half the record is worse than one that is
// awkward to read.

import 'package:cystera/core/cycle/cycle_forecast.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/hirsutism/mfg_models.dart';
import 'package:cystera/core/labs/lab_models.dart';
import 'package:cystera/core/labs/lab_repository.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/log/symptom_catalogue.dart';
import 'package:cystera/core/meds/dose_history.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:cystera/core/metrics/metric_models.dart';
import 'package:cystera/core/report/csv_export.dart';
import 'package:cystera/core/report/doctor_report.dart';
import 'package:cystera/core/report/forecast_line.dart';
import 'package:cystera/core/report/report_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixed Tuesday, so no assertion here depends on a real clock.
final DateTime today = DateTime(2026, 9, 22);

/// Four 28-day cycles ending before [today], which is enough for a window.
List<DateTime> regularPeriods() {
  final first = DateTime(2026, 6, 2);
  return [
    for (var cycle = 0; cycle < 4; cycle++)
      for (var day = 0; day < 4; day++)
        DayKey.addDays(first, cycle * 28 + day),
  ];
}

ReportInput emptyInput() => ReportInput(
      today: today,
      days: const [],
      marks: const [],
      medications: const [],
      settings: const CycleSettings(),
      metrics: MetricPrefs.none,
    );

/// A result as a person types it in: the number, and the unit and range exactly as
/// the laboratory printed them.
LabResult lab({
  String id = 'lab_1',
  String? analyteId,
  String? label,
  required DateTime day,
  required double value,
  String unit = 'ng/mL',
  String? range,
  String? labName,
  String? note,
}) =>
    LabResult(
      id: id,
      analyteId: analyteId,
      label: label,
      day: day,
      value: value,
      unit: unit,
      rangeText: range,
      labName: labName,
      note: note,
    );

/// The rendered PDF as text, for searching. Content streams are WinAnsi, so only
/// plain ASCII is safe to assert on — the em dashes come back as high bytes.
String pdfText(List<int> bytes) => String.fromCharCodes(bytes);

/// The same text with the layout's line wrapping undone: each wrapped line is
/// a separate `(...) Tj ET BT ... Td (...) ` run, so the operator run between
/// two fragments is removed first, then all whitespace is collapsed. A
/// sentence broken across three lines is then one sentence again — which is
/// what `contains` over a paragraph has to see. Em dashes are still WinAnsi
/// high bytes; assert ASCII only (see [pdfText]).
String pdfWords(String text) => text
    .replaceAll(RegExp(r'\)\s*Tj\sET\sBT[^()]*T[dm]\s+\('), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('the PDF is a real PDF', () {
    test('it starts with the header every reader looks for', () {
      final bytes = buildDoctorReportPdf(emptyInput());
      expect(String.fromCharCodes(bytes.take(8)), '%PDF-1.4');
    });

    test('it ends with the end-of-file marker, with no truncation', () {
      final bytes = buildDoctorReportPdf(emptyInput());
      expect(String.fromCharCodes(bytes).trimRight(), endsWith('%%EOF'));
    });

    test('it carries an xref table, so a viewer can seek', () {
      final bytes = buildDoctorReportPdf(emptyInput());
      expect(pdfText(bytes), contains('xref'));
      expect(pdfText(bytes), contains('trailer'));
    });

    test('an empty record still produces a document that says so', () {
      final bytes = buildDoctorReportPdf(emptyInput());
      final text = pdfText(bytes);
      expect(text, contains('cycle and symptom record'));
      expect(text, contains('No period days are recorded'));
      expect(text, contains('No symptoms are recorded'));
    });
  });

  group('what the report prints', () {
    test('the cycle section names each period and the cycle length that followed',
        () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: [
          for (final day in regularPeriods())
            CycleMark(day: day, kind: CycleMarkKind.period),
        ],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
      );
      final text = pdfText(buildDoctorReportPdf(input));
      expect(text, contains('Cycles'));
      // Three completed cycles of 28 days follow the four runs, and the newest one
      // has no length yet.
      expect(text, contains('28 days'));
      expect(text, contains('in progress'));
    });

    test('a symptom is listed with the days at each level, counted', () {
      final days = [
        DayLog(day: DateTime(2026, 9, 1), entries: const {'acne': Severity.mild}),
        DayLog(day: DateTime(2026, 9, 2), entries: const {'acne': Severity.mild}),
        DayLog(day: DateTime(2026, 9, 3), entries: const {'acne': Severity.severe}),
      ];
      final text = pdfText(
        buildDoctorReportPdf(emptyInput().copyWithDays(days)),
      );
      expect(text, contains('Acne'));
      expect(text, contains('3 days'));
      expect(text, contains('2 mild'));
      expect(text, contains('1 severe'));
      // A level with no days is not printed, so the line reads as a count of what
      // happened rather than a scale with gaps in it.
      expect(text, isNot(contains('0 moderate')));
    });

    test('the denominator is stated: days with no decision are not symptom-free',
        () {
      final days = [
        DayLog(day: DateTime(2026, 9, 1), entries: const {'acne': Severity.mild}),
        // A day with nothing at all on it, which the app never opened.
        DayLog(day: DateTime(2026, 9, 2)),
        DayLog(day: DateTime(2026, 9, 3), nothing: true),
      ];
      final text = pdfText(buildDoctorReportPdf(emptyInput().copyWithDays(days)));
      expect(text, contains('2 days have a symptom decision'));
    });

    test('a medication that was logged is counted over the days it existed', () {
      final days = [
        DayLog(day: DateTime(2026, 9, 1), meds: const {'med_1': MedTake.taken}),
        DayLog(day: DateTime(2026, 9, 2), meds: const {'med_1': MedTake.skipped}),
        DayLog(day: DateTime(2026, 9, 3)),
      ];
      final input = ReportInput(
        today: today,
        days: days,
        marks: const [],
        medications: const [
          Medication(
            id: 'med_1',
            name: 'Vitamin D',
            kind: MedKind.supplement,
            dose: '1000 IU',
            addedDay: null,
          ),
        ],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
      );
      final text = pdfText(buildDoctorReportPdf(input));
      expect(text, contains('Vitamin D'));
      expect(text, contains('1000 IU'));
      expect(text, contains('taken on 1 day'));
      expect(text, contains('skipped on 1'));
      // The unrecorded day is stated rather than silently folded into the skips.
      expect(text, contains('nothing recorded on 1'));
    });

    test('a measurement is summarised by its range and mean', () {
      final days = [
        DayLog(
          day: DateTime(2026, 9, 1),
          metrics: const {
            MetricKind.weight: DayMetric(kind: MetricKind.weight, value: 60),
          },
        ),
        DayLog(
          day: DateTime(2026, 9, 2),
          metrics: const {
            MetricKind.weight: DayMetric(kind: MetricKind.weight, value: 62),
          },
        ),
      ];
      final input = ReportInput(
        today: today,
        days: days,
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: const MetricPrefs(enabled: {MetricKind.weight}),
      );
      final text = pdfText(buildDoctorReportPdf(input));
      expect(text, contains('Weight'));
      expect(text, contains('2 readings'));
      expect(text, contains('lowest 60.0 kg'));
      expect(text, contains('highest 62.0 kg'));
      expect(text, contains('mean 61.0 kg'));
    });

    test('a metric that was switched on but never used is said to be empty', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: const MetricPrefs(enabled: {MetricKind.sleep}),
      );
      final text = pdfText(buildDoctorReportPdf(input));
      expect(text, contains('Sleep'));
      expect(text, contains('nothing recorded'));
    });

    test('mucus is counted in days, never averaged into a word', () {
      final days = [
        DayLog(
          day: DateTime(2026, 9, 1),
          metrics: const {
            MetricKind.mucus: DayMetric(kind: MetricKind.mucus, value: 1),
          },
        ),
        DayLog(
          day: DateTime(2026, 9, 2),
          metrics: const {
            MetricKind.mucus: DayMetric(kind: MetricKind.mucus, value: 3),
          },
        ),
      ];
      final input = ReportInput(
        today: today,
        days: days,
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: const MetricPrefs(enabled: {MetricKind.mucus}),
      );
      final text = pdfText(buildDoctorReportPdf(input));
      expect(text, contains('described on record'));
      expect(text, contains('not read as a fertile window'));
      // "mean Sticky" would be a number pretending to be a word.
      expect(text, isNot(contains('mean')));
    });

    test('a note is printed in the user own words, dated', () {
      final days = [
        DayLog(day: DateTime(2026, 9, 4), note: 'Saw the GP about cramps'),
      ];
      final text = pdfText(buildDoctorReportPdf(emptyInput().copyWithDays(days)));
      expect(text, contains('Saw the GP about cramps'));
      expect(text, contains('4 Sep 2026'));
    });
  });

  group('the CSV', () {
    test('it opens with the tidy header, one row per fact', () {
      final csv = buildCsv(emptyInput());
      expect(csv.split('\n').first, 'kind,day,item,detail,value');
    });

    test('a symptom, a cycle day and a note each get their own row', () {
      final days = [
        DayLog(
          day: DateTime(2026, 9, 1),
          cycleMark: CycleMark(
            day: DateTime(2026, 9, 1),
            kind: CycleMarkKind.period,
            flow: FlowLevel.medium,
          ),
          entries: const {'acne': Severity.moderate},
          note: 'Started today',
        ),
      ];
      final csv = buildCsv(emptyInput().copyWithDays(days));
      expect(csv, contains('cycle,2026-09-01,period,,medium'));
      // The level is written with the word the app shows on the tap target, so a
      // spreadsheet reads the same sentence a person does.
      expect(csv, contains('symptom,2026-09-01,acne,,2 (Moderate)'));
      expect(csv, contains('note,2026-09-01,,,Started today'));
    });

    test('a stated nothing is a row, so the day is not read as missing', () {
      final days = [DayLog(day: DateTime(2026, 9, 1), nothing: true)];
      expect(buildCsv(emptyInput().copyWithDays(days)),
          contains('nothing,2026-09-01,,,yes'));
    });

    test('a measurement carries its unit-less value and its detail', () {
      final days = [
        DayLog(
          day: DateTime(2026, 9, 1),
          metrics: const {
            MetricKind.exercise: DayMetric(
              kind: MetricKind.exercise,
              value: 45,
              detail: 'Walking, quickly',
            ),
          },
        ),
      ];
      final csv = buildCsv(emptyInput().copyWithDays(days));
      expect(csv, contains('metric,2026-09-01,exercise,"Walking, quickly",45.0'));
    });

    test('a cell with a comma or a quote is escaped rather than breaking the row',
        () {
      final days = [
        DayLog(day: DateTime(2026, 9, 1), note: 'Said "much better", mostly'),
      ];
      final csv = buildCsv(emptyInput().copyWithDays(days));
      expect(csv, contains('"Said ""much better"", mostly"'));
    });

    test('the symptom ids are mapped to their labels at the end of the file', () {
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'user_1_fog', label: 'Brain fog'),
      ]);
      addTearDown(SymptomCatalogue.clearCustom);

      final days = [
        DayLog(day: DateTime(2026, 9, 1), entries: const {'user_1_fog': Severity.mild}),
      ];
      final csv = buildCsv(emptyInput().copyWithDays(days));
      expect(csv, contains('symptom_label,id,label'));
      expect(csv, contains('symptom_label,user_1_fog,Brain fog'));
      // Only ids that actually appear get a row: the block exists to resolve what
      // is in the file, not to dump the whole catalogue into it.
      expect(csv, isNot(contains('symptom_label,acne')));
    });

    test('an id nothing recognises is still mapped, falling back to the id', () {
      final days = [
        DayLog(day: DateTime(2026, 9, 1), entries: const {'mystery': Severity.mild}),
      ];
      final csv = buildCsv(emptyInput().copyWithDays(days));
      expect(csv, contains('symptom_label,mystery,mystery'));
    });

    test('a blood test is one row, with its printed range and its unit', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(
            analyteId: 'hba1c',
            day: DateTime(2026, 8, 12),
            value: 5.4,
            unit: '%',
            range: '< 5.7',
          ),
        ],
      );
      expect(buildCsv(input), contains('lab,2026-08-12,HbA1c,< 5.7,5.4 %'));
    });

    test('a result with no unit still fills the value column', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [lab(analyteId: 'amh', day: DateTime(2026, 8, 12), value: 4.2, unit: '')],
      );
      expect(buildCsv(input), contains('lab,2026-08-12,AMH,,4.2'));
    });

    test('the lab name and the note get their own block rather than one cell', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(
            analyteId: 'hba1c',
            day: DateTime(2026, 8, 12),
            value: 5.4,
            unit: '%',
            labName: 'City Lab',
            note: 'after fasting',
          ),
        ],
      );
      final csv = buildCsv(input);
      expect(csv, contains('lab_detail,day,item,lab,note'));
      expect(csv, contains('lab_detail,2026-08-12,HbA1c,City Lab,after fasting'));
    });

    test('a value alone adds no second block', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [lab(analyteId: 'amh', day: DateTime(2026, 8, 12), value: 4.2, unit: 'ng/mL')],
      );
      final csv = buildCsv(input);
      expect(csv, contains('lab,2026-08-12,AMH,,4.2 ng/mL'));
      expect(csv, isNot(contains('lab_detail')));
    });

    test('a result outside the window is not exported', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labsFrom: DateTime(2024, 9, 22),
        labs: [
          lab(id: 'old', label: 'Vitamin D', day: DateTime(2021, 3, 1), value: 40, unit: 'nmol/L'),
          lab(id: 'new', analyteId: 'amh', day: DateTime(2026, 8, 1), value: 4.2, unit: 'ng/mL'),
        ],
      );
      final csv = buildCsv(input);
      expect(csv, contains('lab,2026-08-01,AMH,'));
      expect(csv, isNot(contains('Vitamin D')));
    });

    test('a custom name carrying a comma is escaped rather than breaking the row',
        () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(label: 'Vitamin D, 25-OH', day: DateTime(2026, 8, 1), value: 41, unit: 'nmol/L'),
        ],
      );
      expect(buildCsv(input), contains('lab,2026-08-01,"Vitamin D, 25-OH",,41 nmol/L'));
    });

    test('the medications are mapped with their dose and kind', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [
          Medication(
            id: 'med_1',
            name: 'Metformin',
            kind: MedKind.medication,
            dose: '500 mg',
          ),
        ],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
      );
      final csv = buildCsv(input);
      expect(csv, contains('med_label,id,name,dose,kind'));
      expect(csv, contains('med_label,med_1,Metformin,500 mg,Medication'));
    });

    test('a dated dose entry is one row, keyed by its medication id and '
        'ordered oldest first', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        doseEvents: [
          // Written newest-first on purpose: the file orders them, not the
          // caller, or two exports of one record could differ.
          MedDoseEvent(
            id: 'dose_2',
            medicationId: 'med_1',
            day: DateTime(2026, 9, 1),
            kind: DoseEventKind.changed,
            dose: '500 mg',
          ),
          MedDoseEvent(
            id: 'dose_1',
            medicationId: 'med_1',
            day: DateTime(2026, 8, 12),
            kind: DoseEventKind.started,
            dose: '1000 mg',
          ),
          MedDoseEvent(
            id: 'dose_3',
            medicationId: 'med_1',
            day: DateTime(2026, 9, 10),
            kind: DoseEventKind.stopped,
          ),
        ],
      );
      final csv = buildCsv(input);

      final first = 'med_dose,2026-08-12,med_1,started,1000 mg';
      final second = 'med_dose,2026-09-01,med_1,changed,500 mg';
      final third = 'med_dose,2026-09-10,med_1,stopped,';
      expect(csv, contains(first));
      expect(csv, contains(second));
      // A stop carries no dose — the value column is empty, not borrowed from
      // the dose that was in force.
      expect(csv.split('\n'), contains(third));
      expect(csv.indexOf(first) < csv.indexOf(second), isTrue);
      expect(csv.indexOf(second) < csv.indexOf(third), isTrue);
    });

    test('with no entries dated no med_dose row appears', () {
      final csv = buildCsv(emptyInput());
      expect(csv, isNot(contains('med_dose,')));
    });
  });

  group('the blood tests in the report', () {
    test('a result is printed with the lab unit and the range as printed', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(
            analyteId: 'hba1c',
            day: DateTime(2026, 8, 12),
            value: 5.4,
            unit: '%',
            range: '< 5.7',
            labName: 'City Lab',
          ),
        ],
      );
      final text = pdfText(buildDoctorReportPdf(input));

      expect(text, contains('Blood tests, as your reports printed them'));
      expect(text, contains('HbA1c'));
      expect(text, contains('12 Aug 2026'));
      expect(text, contains('5.4 %'));
      expect(text, contains('< 5.7'));
      expect(text, contains('City Lab'));
      // The range is labelled as the laboratory's own, in those words.
      expect(text, contains('range as printed'));
    });

    test('a result with no range on the report says so rather than leaving a gap',
        () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(analyteId: 'amh', day: DateTime(2026, 8, 12), value: 4.2, unit: 'ng/mL'),
        ],
      );
      expect(
        pdfText(buildDoctorReportPdf(input)),
        contains('no range on the report'),
      );
    });

    test('an unread record prints nothing about blood tests', () {
      // `labs` null is "not read", which is not the same fact as "none entered".
      final text = pdfText(buildDoctorReportPdf(emptyInput()));
      expect(text, isNot(contains('Blood tests')));
    });

    test('a record with none entered says exactly that', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: const [],
      );
      expect(
        pdfText(buildDoctorReportPdf(input)),
        contains('No blood-test results have been entered'),
      );
    });

    test('the section carries no verdict, only the figures', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(
            analyteId: 'hba1c',
            day: DateTime(2026, 8, 12),
            value: 9.1,
            unit: '%',
            range: '< 5.7',
          ),
        ],
      );
      final text = pdfText(buildDoctorReportPdf(input));

      // A number far outside the printed range, printed without a judgement.
      expect(text, contains('9.1 %'));
      // Checked as whole words rather than as substrings: "low" sits inside
      // "followed", and a substring test on a PDF's own syntax finds everything.
      final words = text.toLowerCase().split(RegExp(r'[^a-z]+')).toSet();
      for (final word in ['abnormal', 'normal', 'high', 'low', 'elevated']) {
        expect(words.contains(word), isFalse, reason: word);
      }
      // And it says in words that no assessment was made.
      expect(text, contains('made no assessment'));
    });

    test('one test in two units is listed in both, with no conversion', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(
            id: 'a',
            analyteId: 'testosterone',
            day: DateTime(2026, 1, 10),
            value: 1.8,
            unit: 'nmol/L',
          ),
          lab(
            id: 'b',
            analyteId: 'testosterone',
            day: DateTime(2026, 8, 10),
            value: 52,
            unit: 'ng/dL',
          ),
        ],
      );
      final text = pdfText(buildDoctorReportPdf(input));

      expect(text, contains('nmol/L'));
      expect(text, contains('ng/dL'));
      expect(text, contains('No conversion has been applied'));
    });

    test('a result before the window is left out, and the count of older ones is '
        'stated', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labsFrom: DateTime(2024, 9, 22),
        labs: [
          lab(
            id: 'old',
            label: 'Vitamin D',
            day: DateTime(2021, 3, 1),
            value: 40,
            unit: 'nmol/L',
          ),
          lab(
            id: 'new',
            analyteId: 'amh',
            day: DateTime(2026, 8, 1),
            value: 4.2,
            unit: 'ng/mL',
          ),
        ],
      );
      final text = pdfText(buildDoctorReportPdf(input));

      expect(text, contains('AMH'));
      expect(text, isNot(contains('Vitamin D')));
      expect(text, contains('earlier result'));
      expect(text, contains('not listed above'));
    });

    test('a custom test keeps the words the user typed', () {
      final input = ReportInput(
        today: today,
        days: const [],
        marks: const [],
        medications: const [],
        settings: const CycleSettings(),
        metrics: MetricPrefs.none,
        labs: [
          lab(
            label: 'Vitamin D',
            day: DateTime(2026, 8, 1),
            value: 41,
            unit: 'nmol/L',
            range: '75–250',
            note: 'after 12 hours fasting',
          ),
        ],
      );
      final text = pdfText(buildDoctorReportPdf(input));

      expect(text, contains('Vitamin D'));
      expect(text, contains('41 nmol/L'));
      expect(text, contains('75'));
      expect(text, contains('after 12 hours fasting'));
    });
  });

  group('the forecast line', () {
    test('a window is printed as a date range, in plain words', () {
      final forecast = predictCycle(
        marks: [
          for (final day in regularPeriods())
            CycleMark(day: day, kind: CycleMarkKind.period),
        ],
        today: today,
        settings: const CycleSettings(),
      );
      final line = forecastReportLine(forecast, today);
      expect(line, isNotNull);
      expect(line, contains('expects the next period'));
    });

    test('a late period is stated as late, and the window is not moved to hide it',
        () {
      final forecast = ForecastWindow(
        earliest: DateTime(2026, 8, 1),
        latest: DateTime(2026, 8, 5),
        series: predictCycle(
          marks: const [],
          today: today,
          settings: const CycleSettings(),
        ).series,
      );
      final line = forecastReportLine(forecast, today)!;
      expect(line, contains('past it'));
      expect(line, contains('not shifted forward'));
    });

    test('a refusal prints its reason, so the report is not quietly confident', () {
      final forecast = predictCycle(
        marks: const [],
        today: today,
        settings: const CycleSettings(),
      );
      expect(forecast, isA<ForecastUnavailable>());
      final line = forecastReportLine(forecast, today)!;
      expect(line, contains('No prediction is being made'));
      // The refusal's headline goes into the sentence lower-cased, so the report
      // reads as prose rather than as a heading dropped into a line.
      expect(line.toLowerCase(), contains('no periods recorded yet'));
      expect(line, contains('Record the first day'));
    });

    test('perimenopause reports counts rather than a date', () {
      final forecast = predictCycle(
        marks: [
          for (final day in regularPeriods())
            CycleMark(day: day, kind: CycleMarkKind.period),
        ],
        today: today,
        settings: const CycleSettings(mode: CycleMode.perimenopause),
      );
      final line = forecastReportLine(forecast, today)!;
      expect(line, contains('No date is predicted'));
      expect(line, contains('twelve months'));
      expect(line, isNot(contains('expects the next period')));
    });
  });

  group('the self-check in the report', () {
    ReportInput inputWith({List<MfgCheck> mfgChecks = const []}) => ReportInput(
          today: today,
          days: const [],
          marks: const [],
          medications: const [],
          settings: const CycleSettings(),
          metrics: MetricPrefs.none,
          mfgChecks: mfgChecks,
        );

    final partial = MfgCheck(
      day: DateTime(2026, 9, 12),
      ratings: const {
        MfgArea.upperLip: 1,
        MfgArea.chest: 2,
        MfgArea.thigh: 0,
      },
    );

    test('the section prints its refusal, every rated area in words, and the '
        'coverage of a partial check', () {
      final text = pdfWords(
        pdfText(buildDoctorReportPdf(inputWith(mfgChecks: [partial]))),
      );

      expect(text, contains('Hirsutism self-check'));
      expect(text, contains('The areas are not added together here: a total'),
          reason: 'the refusal is part of the document, not only the app');
      expect(text, contains('12 Sep 2026'));
      expect(text, contains('upper lip sparse'));
      expect(text, contains('chest moderate'));
      expect(text, contains('thigh none'),
          reason: 'a rated none is a claim and prints as one');
      expect(text, contains('3 of 9 areas rated'),
          reason: 'a partial check says so, so the other six areas cannot '
              'read as areas rated none');
      expect(text, isNot(contains('upper abdomen')),
          reason: 'an area nobody rated is simply not in the document');
    });

    test('a complete check still prints words, never a computed figure', () {
      final full = MfgCheck(
        day: DateTime(2026, 9, 10),
        ratings: {for (final area in MfgArea.ordered) area: 4},
      );
      final text = pdfWords(
        pdfText(buildDoctorReportPdf(inputWith(mfgChecks: [full]))),
      );

      expect(text, contains('very severe'));
      expect(text, isNot(contains(' of 9 areas rated')),
          reason: 'nothing to caveat when everything was rated');
    });

    test('with no checks there is no section at all', () {
      final text = pdfText(buildDoctorReportPdf(inputWith()));
      expect(text, isNot(contains('Hirsutism self-check')),
          reason: 'an absence needs no paragraph where nothing exists');
    });

    test('the CSV carries one row per rated area and no total row', () {
      final csv = buildCsv(inputWith(mfgChecks: [partial]));

      expect(csv, contains('mfg,2026-09-12,upper_lip,sparse,1'));
      expect(csv, contains('mfg,2026-09-12,chest,moderate,2'));
      expect(csv, contains('mfg,2026-09-12,thigh,none,0'));
      expect(
        RegExp(r'^mfg,', multiLine: true).allMatches(csv),
        hasLength(3),
        reason: 'three rated areas, three rows — no row the app could fill '
            'with a sum',
      );
      expect(csv, isNot(contains('mfg_total')));
    });
  });

  group('the dose history in the report', () {
    Medication doseMed({
      String id = 'med_1',
      String name = 'Vitamin D',
      String? dose = '1000 IU',
      bool archived = false,
    }) =>
        Medication(
          id: id,
          name: name,
          kind: MedKind.supplement,
          dose: dose,
          archived: archived,
          addedDay: DateTime(2026, 6, 1),
        );

    ReportInput inputWith({
      List<Medication> medications = const [],
      List<MedDoseEvent> doseEvents = const [],
    }) =>
        ReportInput(
          today: today,
          days: const [],
          marks: const [],
          medications: medications,
          settings: const CycleSettings(),
          metrics: MetricPrefs.none,
          doseEvents: doseEvents,
        );

    test('dated entries draw a line, label every band, and repeat as words', () {
      final text = pdfText(buildDoctorReportPdf(inputWith(
        medications: [doseMed()],
        doseEvents: [
          MedDoseEvent(
            id: 'dose_1',
            medicationId: 'med_1',
            day: DateTime(2026, 8, 12),
            kind: DoseEventKind.started,
            dose: '1000 IU',
          ),
          MedDoseEvent(
            id: 'dose_2',
            medicationId: 'med_1',
            day: DateTime(2026, 9, 1),
            kind: DoseEventKind.changed,
            dose: '500 IU',
          ),
        ],
      )));

      expect(text, contains('Dose history'));
      expect(text, contains('are not amounts'),
          reason: 'the figure says out loud that heights are wordings');
      expect(text, contains('Vitamin D'), reason: 'its own subheading');
      // The bullet is ASCII-asserted in halves: the em dash joining them is a
      // WinAnsi high byte on the way back (see pdfText's note).
      expect(text, contains('12 Aug 2026'));
      expect(text, contains('started · 1000 IU'));
      expect(text, contains('1 Sep 2026'));
      expect(text, contains('changed · 500 IU'));
      // The band labels — the dose word above each run — are ASCII-searchable.
      expect(text, contains('1000 IU'));
      expect(text, contains('500 IU'));
    });

    test('with nothing dated the section is absent, and the absence is stated '
        'beside the doses it qualifies', () {
      final text = pdfText(buildDoctorReportPdf(
        inputWith(medications: [doseMed()]),
      ));

      expect(text, isNot(contains('Dose history')),
          reason: 'an empty section of its own would be a page of no news');
      expect(
        text,
        contains('No dose start, change, or stop has been dated'),
        reason: 'but a reader must not take the printed dose for a duration',
      );
    });
    test('with no medications at all nothing is claimed about doses', () {
      final text = pdfText(buildDoctorReportPdf(emptyInput()));
      expect(text, isNot(contains('Dose history')));
      expect(text, isNot(contains('No dose start')));
    });

    test('one medication dated and another not is said out loud', () {
      final text = pdfText(buildDoctorReportPdf(inputWith(
        medications: [doseMed(), doseMed(id: 'med_2', name: 'Metformin')],
        doseEvents: [
          MedDoseEvent(
            id: 'dose_1',
            medicationId: 'med_1',
            day: DateTime(2026, 8, 12),
            kind: DoseEventKind.started,
            dose: '1000 IU',
          ),
        ],
      )));

      expect(text, contains('Dose history'));
      expect(
        pdfWords(text),
        contains('Medications with no line here have no dated entries at all'),
        reason: 'a missing line must not read as a constant dose',
      );
    });

    test('every entry dated today draws no line, and says so', () {
      final text = pdfText(buildDoctorReportPdf(inputWith(
        medications: [doseMed()],
        doseEvents: [
          MedDoseEvent(
            id: 'dose_1',
            medicationId: 'med_1',
            day: DateTime(2026, 9, 22),
            kind: DoseEventKind.started,
            dose: '1000 IU',
          ),
          MedDoseEvent(
            id: 'dose_2',
            medicationId: 'med_1',
            day: DateTime(2026, 9, 22),
            kind: DoseEventKind.stopped,
          ),
        ],
      )));

      // One date has no width — entries on a *past* day would still draw the
      // state they left in force through today, which is a line worth having.
      expect(pdfWords(text),
          contains('All entries for this medication are dated the same day'));
      expect(text, contains('22 Sep 2026'));
      expect(text, contains('started · 1000 IU'));
      expect(text, contains('stopped'),
          reason: 'the stop is listed, as its own line');
      expect(text.contains('stopped ·'), isFalse,
          reason: 'a stop borrows no dose from anywhere');
    });

    test('an archived medication keeps its name above its history, and is said '
        'to be off the daily list', () {
      final text = pdfText(buildDoctorReportPdf(inputWith(
        medications: [doseMed(archived: true)],
        doseEvents: [
          MedDoseEvent(
            id: 'dose_1',
            medicationId: 'med_1',
            day: DateTime(2026, 8, 12),
            kind: DoseEventKind.stopped,
          ),
        ],
      )));

      expect(text, contains('Vitamin D'));
      expect(text, isNot(contains('medication med_1')),
          reason: 'the builder reads the archived row, so the name is there');
      expect(
        pdfWords(text),
        contains('Not on the daily list now.'),
        reason: 'its presence here is explained, not left to be guessed',
      );
    });
  });

  group('building the bundle from a record', () {
    test('a locked record yields nothing, rather than an empty report', () async {
      final report = await buildReportBundle(
        repository: null,
        settings: const CycleSettings(),
        today: today,
      );
      expect(report, isNull);
    });

    test('it reads the window it says it read, and counts the days it found',
        () async {
      final repo = FakeLogRepository();
      await repo.setSeverity(DateTime(2026, 9, 1), 'acne', Severity.mild);
      await repo.setSeverity(DateTime(2026, 9, 2), 'acne', Severity.mild);
      // Just outside a 24-month window, so it must not appear.
      await repo.setSeverity(DateTime(2020, 1, 1), 'acne', Severity.mild);

      final report = await buildReportBundle(
        repository: repo,
        settings: const CycleSettings(),
        today: today,
      );
      expect(report, isNotNull);
      expect(report!.dayCount, 2);
      expect(report.monthCount, defaultReportMonths);
      expect(report.baseName, 'cystera-report-2026-09-22');
      expect(report.pdfName, 'cystera-report-2026-09-22.pdf');
      expect(report.csvName, 'cystera-report-2026-09-22.csv');
    });

    test('the cycle marks come from the days, so the report and the chart agree',
        () async {
      final repo = FakeLogRepository();
      final marks = regularPeriods();
      await repo.markCycleDays(marks);

      final report = await buildReportBundle(
        repository: repo,
        settings: const CycleSettings(),
        today: today,
      );
      final text = pdfText(report!.pdf);
      expect(text, contains('Cycles'));
      expect(text, contains('28 days'));
    });

    test('the prediction the app is giving reaches the report', () async {
      final repo = FakeLogRepository();
      await repo.markCycleDays(regularPeriods());
      final forecast = predictCycle(
        marks: [
          for (final day in regularPeriods())
            CycleMark(day: day, kind: CycleMarkKind.period),
        ],
        today: today,
        settings: const CycleSettings(),
      );

      final report = await buildReportBundle(
        repository: repo,
        settings: const CycleSettings(),
        today: today,
        forecastLine: forecastReportLine(forecast, today),
      );
      expect(pdfText(report!.pdf), contains('expects the next period'));
    });

    test('the dose history and the archived list reach both files', () async {
      final repo = FakeLogRepository();
      await repo.upsertMedication(const Medication(
        id: 'med_a',
        name: 'Metformin',
        kind: MedKind.medication,
        dose: '500 mg',
        archived: true,
        addedDay: null,
      ));
      await repo.addDoseEvent(MedDoseEvent(
        id: 'dose_1',
        medicationId: 'med_a',
        day: DateTime(2026, 8, 12),
        kind: DoseEventKind.started,
        dose: '500 mg',
      ));

      final report = await buildReportBundle(
        repository: repo,
        settings: const CycleSettings(),
        today: today,
      );

      final text = pdfText(report!.pdf);
      expect(text, contains('Dose history'));
      expect(text, contains('12 Aug 2026'));
      expect(text, contains('started · 500 mg'));
      expect(text, contains('Metformin'),
          reason: 'a removed medication still has its history printed — under '
              'its name, not its id');
      expect(text, isNot(contains('medication med_a')));
      expect(report.csv, contains('med_dose,2026-08-12,med_a,started,500 mg'));
      expect(report.csv, contains('med_label,med_a,Metformin'),
          reason: 'the label block covers archived rows too, or its rows are '
              'unreadable in a spreadsheet');
    });

    test('an empty record still builds, and both files are produced', () async {
      final report = await buildReportBundle(
        repository: FakeLogRepository(),
        settings: const CycleSettings(),
        today: today,
      );
      expect(report!.dayCount, 0);
      expect(report.pdf, isNotEmpty);
      expect(report.csv, contains('kind,day,item,detail,value'));
    });

    test('the blood tests reach both files, from the lab repository', () async {
      final labs = FakeLabRepository();
      await labs.upsert(lab(
        analyteId: 'hba1c',
        day: DateTime(2026, 8, 12),
        value: 5.4,
        unit: '%',
        range: '< 5.7',
      ));

      final report = await buildReportBundle(
        repository: FakeLogRepository(),
        settings: const CycleSettings(),
        today: today,
        labRepository: labs,
      );

      expect(pdfText(report!.pdf), contains('Blood tests, as your reports printed them'));
      expect(pdfText(report.pdf), contains('HbA1c'));
      expect(report.csv, contains('lab,2026-08-12,HbA1c,< 5.7,5.4 %'));
    });

    test('with no lab repository the section is left out, not called empty',
        () async {
      final report = await buildReportBundle(
        repository: FakeLogRepository(),
        settings: const CycleSettings(),
        today: today,
      );
      // The report is built by a build that could not read the results; printing
      // "none entered" would be a claim about the record it never made.
      expect(pdfText(report!.pdf), isNot(contains('Blood tests')));
      expect(report.csv, isNot(contains('lab,')));
    });
  });
}

/// A convenience for the report tests: the same input with a different set of days.
extension on ReportInput {
  ReportInput copyWithDays(List<DayLog> days) => ReportInput(
        today: today,
        days: days,
        marks: marks,
        medications: medications,
        doseEvents: doseEvents,
        mfgChecks: mfgChecks,
        settings: settings,
        metrics: metrics,
        forecastLine: forecastLine,
        labs: labs,
        labsFrom: labsFrom,
      );
}
