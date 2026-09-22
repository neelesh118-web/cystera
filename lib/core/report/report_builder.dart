/// Assembles the doctor report from what the record holds.
///
/// Kept out of the controller so the whole path — read range, shape the input, lay
/// out the PDF, write the CSV — is one function a host test can call with an
/// in-memory repository. The controller only decides *when* to build it.
library;

import 'dart:typed_data';

import '../cycle/cycle_settings.dart';
import '../labs/lab_repository.dart';
import '../log/day_key.dart';
import '../log/log_models.dart';
import '../log/log_repository.dart';
import 'csv_export.dart';
import 'doctor_report.dart';

/// What a finished report is: two files' worth of bytes and the names to save them
/// under.
class ReportBundle {
  const ReportBundle({
    required this.pdf,
    required this.csv,
    required this.baseName,
    required this.dayCount,
    required this.monthCount,
  });

  final Uint8List pdf;
  final String csv;

  /// Without an extension — the same stem is used for the PDF and the CSV, so the
  /// two files sort together in a folder.
  final String baseName;

  final int dayCount;
  final int monthCount;

  String get pdfName => '$baseName.pdf';
  String get csvName => '$baseName.csv';
}

/// How far back the report reaches by default.
///
/// Two years is longer than a gynaecologist usually asks for and shorter than a
/// phone full of history, and it is the window the cycle chart already draws. The
/// cost of the wider window is a slower first build, not a bigger file — the PDF
/// prints only what it finds.
const int defaultReportMonths = 24;

/// Builds the report, or null when the record is not open.
///
/// Null rather than an empty report: a report of zero days that looks like a real
/// report is worse than a button that stays disabled, and the settings screen has
/// nothing to show behind the lock anyway.
Future<ReportBundle?> buildReportBundle({
  required LogRepository? repository,
  required CycleSettings settings,
  required DateTime today,
  String? forecastLine,
  int months = defaultReportMonths,
  LabRepository? labRepository,
}) async {
  if (repository == null) return null;

  final day = DayKey.dayOf(today);
  // The month count is turned into days with a fixed 31-day month rather than a
  // calendar walk: it only ever widens the window by a day or two, and a report
  // that included one extra blank day is not a correctness problem.
  final from = DayKey.addDays(day, -(months * 31));
  final loaded = await repository.loadRange(from, day);
  final days = loaded.values.toList();

  final marks = <CycleMark>[
    for (final log in days) ?log.cycleMark,
  ];

  final input = ReportInput(
    today: day,
    days: days,
    marks: marks,
    // Archived medications are included, unlike the daily list: their takes
    // and dose history are part of the record the report exists to print, and
    // a `stopped` entry on a medication the user has since removed is exactly
    // the fact a clinician needs and exactly the one a filtered read would
    // drop (`docs/meds.md`, "archived rather than deleted").
    medications: await repository.medications(includeArchived: true),
    doseEvents: await repository.doseEvents(),
    mfgChecks: await repository.mfgChecks(),
    settings: settings,
    metrics: await repository.metricPrefs(),
    forecastLine: forecastLine,
    // Every result on record rather than the report's window, and the window's
    // start handed over with them: a doctor reads the report's own "last 24
    // months" line, and a blood test from three years ago must not appear under it
    // as though it were recent. The section filters and says how many it left out.
    labs: labRepository == null ? null : await labRepository.load(),
    labsFrom: from,
  );

  return ReportBundle(
    pdf: buildDoctorReportPdf(input),
    csv: buildCsv(input),
    baseName: 'cystera-report-${DayKey.of(day)}',
    dayCount: input.days.length,
    monthCount: months,
  );
}
