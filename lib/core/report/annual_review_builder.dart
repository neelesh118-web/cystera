/// Reads the record and assembles the annual review pack.
///
/// Kept out of both the controller and the pure module for the same reason
/// `report_builder.dart` is: the whole path — read a year of days, shape the
/// input, lay out the page — is one function a host test can call with an
/// in-memory repository. The controller only decides *when* to build it.
library;

import 'dart:typed_data';

import '../cycle/cycle_settings.dart';
import '../labs/lab_repository.dart';
import '../log/day_key.dart';
import '../log/log_repository.dart';
import 'annual_review.dart';

/// What a finished pack is: the bytes of the one page and the name to save it
/// under.
class AnnualReviewPack {
  const AnnualReviewPack({required this.pdf, required this.baseName});

  final Uint8List pdf;

  /// Without an extension — `pdfName` completes it.
  final String baseName;

  String get pdfName => '$baseName.pdf';
}

/// How far back the pack reads: the twelve months the checklist asks about,
/// widened by the same fixed-31-day month the doctor report uses so a cycle that
/// started on the window's edge is not cut in half by arithmetic on months.
const int annualReviewMonths = 12;

/// Builds the pack, or null when the record is not open.
///
/// Null rather than an empty pack for the same reason the report returns null:
/// a checklist of nothing that looks like a real checklist is worse than an
/// action that stays disabled.
Future<AnnualReviewPack?> buildAnnualReviewPack({
  required LogRepository? repository,
  required CycleSettings settings,
  required DateTime today,
  DateTime? lastReviewDay,
  LabRepository? labRepository,
  int months = annualReviewMonths,
}) async {
  if (repository == null) return null;

  final day = DayKey.dayOf(today);
  final from = DayKey.addDays(day, -(months * 31));
  final loaded = await repository.loadRange(from, day);
  final days = loaded.values.toList();

  final input = AnnualReviewInput(
    today: day,
    days: days,
    marks: [
      for (final log in days) ?log.cycleMark,
    ],
    medications: await repository.medications(),
    settings: settings,
    metrics: await repository.metricPrefs(),
    // Unread stays null — the pack's two lab rows say "not read" rather than
    // claiming nothing is on record, which is the distinction the pure module
    // defends and this call site exists to preserve.
    labs: labRepository == null ? null : await labRepository.load(),
    lastReviewDay: lastReviewDay == null ? null : DayKey.dayOf(lastReviewDay),
  );

  return AnnualReviewPack(
    pdf: buildAnnualReviewPdf(input),
    baseName: 'cystera-annual-review-${DayKey.of(day)}',
  );
}
