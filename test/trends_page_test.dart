// The Trends screen through the real app with a fake repository.
//
// What is asserted here rather than in the engine tests: that the gate is on
// screen next to the finding, that a record which cannot support one gets a
// sentence instead of an empty chart, that the cap says it bit, and that a read
// which failed is not drawn as a record with nothing in it.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/log/symptom_catalogue.dart';
import 'package:cystera/core/log/symptom_correlation.dart';
import 'package:cystera/core/metrics/metric_models.dart';
import 'package:cystera/core/widgets/patterns_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

/// Three finished 28-day cycles, ending with a start 21 days before [fixedToday].
final List<DateTime> starts = [
  for (var i = 0; i <= 3; i++) DayKey.addDays(DateTime(2026, 6, 9), i * 28),
];

/// What the fixture logs, in the counts the gate is stated in.
const String symptomId = 'irritability';

/// The page's own scrolling list. Found by direction rather than by type, and
/// straight from the tree rather than as a descendant of a ListView — a finder
/// for "a ListView inside a ListView" matches nothing, which is a mistake that
/// hides itself whenever the target happens to be on screen already.
Finder pageList() => find.byWidgetPredicate(
      (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
    );

class _Fixture {
  /// Four of the five days before a period carry the symptom, and one of the ten
  /// other days: a rate of 80% against 10%, which is the shape every assertion in
  /// this file is written against.
  static const int preWithSymptom = 4;
  static const int otherWithSymptom = 1;
  static const int cycles = 3;

  final Map<String, Map<String, Severity>> _byDay = {};

  void _log(DateTime day, String symptom, Severity severity) =>
      _byDay.putIfAbsent(DayKey.of(day), () => {})[symptom] = severity;

  Future<void> write(FakeLogRepository repository) async {
    for (var i = 0; i < cycles; i++) {
      final start = starts[i];
      final next = starts[i + 1];

      for (var d = 0; d < 5; d++) {
        _log(
          DayKey.addDays(next, -(5 - d)),
          d < preWithSymptom ? symptomId : 'brain_fog',
          d < preWithSymptom ? Severity.moderate : Severity.mild,
        );
      }
      for (var d = 0; d < 10; d++) {
        _log(
          DayKey.addDays(start, d + 1),
          d < otherWithSymptom ? symptomId : 'brain_fog',
          d < otherWithSymptom ? Severity.moderate : Severity.mild,
        );
      }
    }
    for (final entry in _byDay.entries) {
      final parsed = DayKey.parse(entry.key)!;
      for (final symptom in entry.value.entries) {
        await repository.setSeverity(parsed, symptom.key, symptom.value);
      }
    }
    await repository.markCycleDays(starts, flow: FlowLevel.medium);
  }
}

void main() {
  late TestAppLock lock;

  setUp(() async {
    lock = await TestAppLock.create();
  });

  tearDown(() => lock.dispose());

  /// Opens the app on the Trends view — the Patterns destination's second segment —
  /// which is where the window gets read.
  Future<void> pumpTrends(
    WidgetTester tester, {
    required LogRepository repository,
    bool phoneSized = false,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize =
        phoneSized ? const Size(1080, 2340) : const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CysteraApp(
        lock: lock.controller,
        autoInitialiseLock: false,
        logRepository: repository,
        clock: () => fixedToday,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Patterns, then its second view. The trends are not a destination of their own
    // any more, so this is the two taps a user makes — and the extra pump between
    // them is the route swap, not a wait for the read.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Patterns'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(
      find.descendant(
        of: find.byType(PatternsSwitcher),
        matching: find.text('Trends'),
      ),
    );
    // One pump for the route, one for the post-frame read, one for the window.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a finding is drawn with both rates and the counts behind them',
      (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    await pumpTrends(tester, repository: repository);

    expect(find.text(Symptom.byId(symptomId)!.label), findsOneWidget);
    expect(
      find.textContaining('1 of the 14 symptoms you log cleared the gate below: '
          'it is at least twice as common in the 5 days before a period started '
          'as on the other days of the same cycles.'),
      findsOneWidget,
    );
    expect(
      find.text('12 of the 15 days before a period started (80%), against 3 of '
          'the 30 other days (10%).'),
      findsOneWidget,
    );
    // The bars carry their numbers, so the drawing can be checked rather than
    // believed.
    expect(find.text('80% — 12 of 15 logged days'), findsOneWidget);
    expect(find.text('10% — 3 of 30 logged days'), findsOneWidget);
    expect(find.textContaining('12 of the 12 were moderate or worse'),
        findsOneWidget);
  });

  testWidgets('the gate and the sample are on the card, not in a tooltip',
      (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    await pumpTrends(tester, repository: repository);

    expect(find.text('THE GATE'), findsOneWidget);
    expect(find.text(CorrelationGate.statement), findsOneWidget);
    expect(
      find.text('15 logged days before period starts and 30 on the other days, '
          'across 3 finished cycles.'),
      findsOneWidget,
    );
    // What the screen does not do is stated on the screen.
    expect(find.textContaining('Correlation, not cause'), findsOneWidget);
    expect(find.textContaining('not a luteal-phase claim'), findsOneWidget);
  });

  testWidgets('the days held out are counted and said', (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    // A bleeding day with the symptom, and a day in the cycle that is still open:
    // both held out, both counted.
    await repository.setSeverity(starts[1], symptomId, Severity.severe);
    await repository.setSeverity(
      DayKey.addDays(starts[3], 12),
      symptomId,
      Severity.severe,
    );
    await pumpTrends(tester, repository: repository);

    expect(
      find.textContaining('Held out of the comparison: 1 on days you were '
          'bleeding, and 1 in the cycle you are in now'),
      findsOneWidget,
    );
  });

  testWidgets('a cap that hid something says so', (tester) async {
    final repository = FakeLogRepository();
    // Four symptoms, all clearing, so one is left off the list.
    final builder = _Fixture();
    await builder.write(repository);
    final extras = SymptomCatalogue.all.take(4).toList();
    for (var i = 0; i < extras.length; i++) {
      for (var cycle = 0; cycle < 3; cycle++) {
        for (var d = 0; d < 5 - i; d++) {
          await repository.setSeverity(
            DayKey.addDays(starts[cycle + 1], -(5 - d)),
            extras[i].id,
            Severity.moderate,
          );
        }
        for (var d = 0; d < 4 - i; d++) {
          await repository.setSeverity(
            DayKey.addDays(starts[cycle], d + 20),
            extras[i].id,
            Severity.moderate,
          );
        }
      }
    }
    await pumpTrends(tester, repository: repository);

    expect(find.textContaining('The strongest'), findsOneWidget);
    expect(find.textContaining('cleared the gate'), findsOneWidget);
  });

  testWidgets('a record that cannot support a finding is refused in words',
      (tester) async {
    await pumpTrends(tester, repository: FakeLogRepository());

    expect(
      find.textContaining('Only 0 finished cycles are on record'),
      findsOneWidget,
    );
    // And the gate is still on screen: a refusal is a result, not a blank page.
    expect(find.text(CorrelationGate.statement), findsOneWidget);
    expect(find.textContaining('Correlation, not cause'), findsOneWidget);
  });

  testWidgets('a read that failed is not drawn as an empty record',
      (tester) async {
    await pumpTrends(tester, repository: _FailingRepository());

    expect(find.textContaining('database is closed'), findsOneWidget);
    expect(find.textContaining('Only 0 finished cycles'), findsNothing);
  });

  testWidgets('the card fits a 360pt phone', (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    // Two findings, so the card is at its tallest realistic size.
    for (var cycle = 0; cycle < 3; cycle++) {
      for (var d = 0; d < 5; d++) {
        await repository.setSeverity(
          DayKey.addDays(starts[cycle + 1], -(5 - d)),
          'bloating',
          Severity.severe,
        );
      }
    }
    await pumpTrends(tester, repository: repository, phoneSized: true);

    final footnote = find.textContaining('Correlation, not cause. Nothing here');
    await tester.dragUntilVisible(footnote, pageList(), const Offset(0, -240));
    await tester.pump();

    // The card is inside the viewport, not merely built: a single tall list item
    // is in the tree even when it runs off the bottom of the screen.
    final viewport = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(footnote).bottom, lessThanOrEqualTo(viewport));
    expect(tester.getRect(footnote).top, greaterThanOrEqualTo(0));
    expect(find.text(Symptom.byId(symptomId)!.label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the parts of Trends that are not built say so', (tester) async {
    await pumpTrends(tester, repository: FakeLogRepository());

    await tester.dragUntilVisible(
      find.text('Still to come on this screen'),
      pageList(),
      const Offset(0, -240),
    );
    await tester.pump();

    expect(find.text('Still to come on this screen'), findsOneWidget);
    expect(
      find.textContaining('A severity distribution'),
      findsOneWidget,
    );
  });

  testWidgets('the cycle lengths are drawn, with the basis stated beside them',
      (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    await pumpTrends(tester, repository: repository);

    await tester.dragUntilVisible(
      find.text('How long each cycle ran'),
      pageList(),
      const Offset(0, -240),
    );
    await tester.pump();

    expect(find.text('How long each cycle ran'), findsOneWidget);
    // Three completed cycles of 28 days: the numbers on the bars, and the basis
    // sentence that says where they came from.
    expect(find.text('28'), findsNWidgets(3));
    expect(find.text('oldest'), findsOneWidget);
    expect(find.text('newest'), findsOneWidget);
    expect(find.textContaining('a spread of 0 days'), findsOneWidget);
  });

  testWidgets('a record too short for a chart gets the number it needs instead',
      (tester) async {
    final repository = FakeLogRepository();
    // One completed cycle only: a second start, and no third.
    await repository.markCycleDays([starts[0], starts[1]]);
    await pumpTrends(tester, repository: repository);

    await tester.dragUntilVisible(
      find.text('How long each cycle ran'),
      pageList(),
      const Offset(0, -240),
    );
    await tester.pump();

    expect(find.text('How long each cycle ran'), findsOneWidget);
    // No bars at all: a chart from one number implies a pattern that is not there.
    expect(find.text('28'), findsNothing);
    expect(find.textContaining('two more will fill this in'), findsOneWidget);
  });

  testWidgets('with nothing switched on the measurements card says exactly that',
      (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    await pumpTrends(tester, repository: repository);

    await tester.dragUntilVisible(
      find.text('No measurements switched on'),
      pageList(),
      const Offset(0, -240),
    );
    await tester.pump();

    expect(find.text('No measurements switched on'), findsOneWidget);
  });

  testWidgets('a measurement is summarised with its count, range and change',
      (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    await repository.writeMetricPrefs(
      const MetricPrefs(enabled: {MetricKind.weight}),
    );
    // Five readings across the window, ending 2 kg heavier than it started.
    const values = [60.0, 60.5, 61.0, 61.5, 62.0];
    for (var i = 0; i < values.length; i++) {
      final day = DayKey.addDays(fixedToday, -(20 - i * 4));
      await repository.setMetric(
        day,
        MetricKind.weight,
        DayMetric(kind: MetricKind.weight, value: values[i]),
      );
    }
    await pumpTrends(tester, repository: repository);

    await tester.dragUntilVisible(
      find.text('The measurements you keep'),
      pageList(),
      const Offset(0, -240),
    );
    await tester.pump();

    expect(find.text('Weight'), findsOneWidget);
    // The count is what stops five points looking like fifty, so it is printed.
    expect(find.textContaining('5 readings'), findsOneWidget);
    expect(find.textContaining('lowest 60.0 kg'), findsOneWidget);
    expect(find.textContaining('highest 62.0 kg'), findsOneWidget);
    expect(find.textContaining('mean 61.0 kg'), findsOneWidget);    // The unit appears once: the formatter carries it, so the change label must
    // not add a second one.
    expect(find.textContaining('from 60.0 kg to 62.0 kg (+2.0 kg)'), findsOneWidget);
  });

  testWidgets('two readings are refused a line and told what the floor is',
      (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    await repository.writeMetricPrefs(
      const MetricPrefs(enabled: {MetricKind.weight}),
    );
    await repository.setMetric(
      DayKey.addDays(fixedToday, -10),
      MetricKind.weight,
      const DayMetric(kind: MetricKind.weight, value: 60),
    );
    await repository.setMetric(
      fixedToday,
      MetricKind.weight,
      const DayMetric(kind: MetricKind.weight, value: 62),
    );
    await pumpTrends(tester, repository: repository);

    await tester.dragUntilVisible(
      find.text('The measurements you keep'),
      pageList(),
      const Offset(0, -240),
    );
    await tester.pump();

    // The summary of what was recorded is still there — the refusal is about the
    // line, not about the numbers. "2 readings" alone matches twice, because the
    // refusal counts them too, so this asserts on the summary sentence itself.
    expect(find.textContaining('2 readings, lowest 60.0 kg'), findsOneWidget);
    expect(find.textContaining('not enough to draw a line from'), findsOneWidget);
  });

  testWidgets('the cycle chart fits a 360pt phone', (tester) async {
    final repository = FakeLogRepository();
    await _Fixture().write(repository);
    await pumpTrends(tester, repository: repository, phoneSized: true);

    await tester.dragUntilVisible(
      find.text('How long each cycle ran'),
      pageList(),
      const Offset(0, -200),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

/// A repository whose reads fail, standing in for a store that closed.
class _FailingRepository extends FakeLogRepository {
  @override
  Future<Map<String, DayLog>> loadRange(DateTime from, DateTime to) async {
    throw StateError('database is closed');
  }
}
