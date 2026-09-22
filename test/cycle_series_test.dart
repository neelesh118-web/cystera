// The derivation every prediction rests on: how many days pass between one
// period starting and the next.
//
// The two mistakes worth a test file of their own are both about what *not* to
// count: the cycle in progress has no length yet, and a long gap is a length
// rather than an outlier to be tidied away. The second one is the reason this app
// exists — an app that drops the outlier tells a person with PCOD that their
// record is regular.

import 'package:cystera/core/cycle/cycle_series.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

/// Days-ago values for period starts, built from the completed cycle lengths
/// [gaps] (oldest first). Deriving the starts from the gaps rather than writing
/// starts by hand is what keeps a test's arithmetic and its claim the same thing.
List<int> startsAgo(List<int> gaps, {int newestAgo = 5}) {
  final out = <int>[newestAgo];
  var cursor = newestAgo;
  for (final gap in gaps.reversed) {
    cursor += gap;
    out.insert(0, cursor);
  }
  return out;
}

/// Marks for periods starting on each day in [starts], running forward from the
/// start — but never into the future, so a period that starts today is one day
/// long, which is what "still going" honestly looks like.
List<CycleMark> periods(List<int> starts, {int length = 4}) => [
      for (final ago in starts)
        for (var i = 0; i < length; i++)
          if (i <= ago)
            CycleMark(
              day: DayKey.addDays(today, -ago + i),
              kind: CycleMarkKind.period,
            ),
    ];

CycleSeries seriesOf(
  List<int> gaps, {
  int newestAgo = 5,
  int length = 4,
}) =>
    CycleSeries.from(
      periods(startsAgo(gaps, newestAgo: newestAgo), length: length),
      today: today,
    );

void main() {
  test('measures the gap from one start to the next, not the period length', () {
    // A 28-day cycle whose periods lasted 5 days: the five days are irrelevant.
    final series = seriesOf([28], length: 5);
    expect(series.lengths, [28]);
    expect(series.completedCycles, 1);
  });

  test('the cycle in progress has no length yet', () {
    // Two completed cycles and a period that started today, so two lengths —
    // not three, and not two lengths that grow by a day each morning.
    final series = seriesOf([28, 28], newestAgo: 0);
    expect(series.lengths, [28, 28]);
    expect(series.lastStart, DayKey.dayOf(today));
    expect(series.lastPeriodLengthDays, isNull);
  });

  test('lengths are oldest first, so the chips read left to right in time', () {
    expect(seriesOf([32, 30, 28]).lengths, [32, 30, 28]);
  });

  test('caps at six cycles and drops the oldest, keeping the newest', () {
    final series = seriesOf([67, 30, 30, 30, 30, 30, 28]);
    expect(series.completedCycles, CycleSeries.basisCycles);
    // The 67-day gap is the oldest and is the one that falls off the end; the
    // 28-day cycle just behind today stays.
    expect(series.lengths, [30, 30, 30, 30, 30, 28]);
    expect(series.spreadDays, 2);
  });

  test('a long gap is kept as a long cycle', () {
    // 90 days between two starts. The app cannot tell a 90-day cycle from three
    // missed months, so it reports the length and lets the refusals deal with
    // it — it does not delete the row that would have shown it.
    expect(seriesOf([90]).lengths, [90]);
    expect(seriesOf([90]).spreadDays, 0);
  });

  test('spread is the distance between the shortest and the longest', () {
    final series = seriesOf([27, 30, 29]);
    expect(series.shortest, 27);
    expect(series.longest, 30);
    expect(series.spreadDays, 3);
  });

  test('an ongoing period has no length, and a finished one does', () {
    expect(seriesOf([30], newestAgo: 0).lastPeriodLengthDays, isNull);
    expect(seriesOf([30], newestAgo: 5, length: 5).lastPeriodLengthDays, 5);
  });

  test('a period that ended before today is not ongoing', () {
    final series = seriesOf([30], newestAgo: 5, length: 5);
    expect(series.runs.first.ongoing, isFalse);
  });

  test('an empty record is empty rather than a zero', () {
    final series = CycleSeries.from(const [], today: today);
    expect(series.lengths, isEmpty);
    expect(series.spreadDays, isNull);
    expect(series.shortest, isNull);
    expect(series.averageDays, isNull);
    expect(series.hasEnough, isFalse);
    expect(series.describeBasis(), contains('No completed cycles'));
  });

  test('a day recorded twice is one day, not a zero-length cycle', () {
    // Through the database this cannot happen — `cycle_mark.day` is a primary
    // key — but the derivation is also fed by the in-memory repository, and a
    // repeated day once produced a 0-day cycle, which makes the spread
    // meaningless and the app refuse to predict for a good record.
    final marks = periods(startsAgo([28]))
      ..addAll(periods(startsAgo([28])));
    final series = CycleSeries.from(marks, today: today);

    expect(series.runs.length, 2);
    expect(series.lengths, [28]);
    expect(series.lengths, isNot(contains(0)));
  });

  test('spotting is not a cycle boundary', () {
    final marks = periods(startsAgo([28]))
      ..add(CycleMark(
        day: DayKey.addDays(today, -20),
        kind: CycleMarkKind.spotting,
      ));
    final series = CycleSeries.from(marks, today: today);
    expect(series.runs.length, 2);
    expect(series.lengths, [28]);
  });

  test('the basis sentence names the lengths, the range and the spread', () {
    final basis = seriesOf([28, 30, 32]).describeBasis();
    expect(basis, contains('last 3 cycles'));
    expect(basis, contains('28 to 32 days'));
    expect(basis, contains('(28, 30, 32)'));
    expect(basis, contains('spread of 4 days'));
  });

  test('one cycle is described in the singular', () {
    expect(seriesOf([28]).describeBasis(), contains('last 1 cycle'));
    expect(seriesOf([28]).describeBasis(), contains('spread of 0 days'));
  });

  test('a mean is rounded, because nobody has a fractional cycle', () {
    // 27, 28, 28 → 27.67 days.
    expect(seriesOf([27, 28, 28]).averageDays, 28);
  });

  test('hasEnough waits for three completed cycles', () {
    expect(seriesOf([28, 30]).hasEnough, isFalse);
    expect(seriesOf([28, 30, 29]).hasEnough, isTrue);
  });
}
