// The adherence arithmetic, which exists to be boring and checkable.
//
// The tests that matter here are not the counts — they are the three claims the
// feature rests on: a day with no tap is not a miss, the window starts when the
// medication did rather than thirty days ago, and there is no percentage anywhere
// in the output. Each of those is a place where an adherence report can be
// perfectly accurate and still tell the user something untrue about their life.

import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/meds/adherence.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

DateTime day(int offset) => DayKey.addDays(today, offset);

Medication med({
  String id = 'med_1',
  String name = 'Vitamin D',
  MedKind kind = MedKind.supplement,
  DateTime? added,
}) =>
    Medication(id: id, name: name, kind: kind, addedDay: added);

/// `{daysAgo: {medicationId: take}}`.
Map<String, Map<String, MedTake>> takes(
  Map<int, Map<String, MedTake>> byDaysAgo,
) =>
    {
      for (final entry in byDaysAgo.entries)
        DayKey.of(day(-entry.key)): entry.value,
    };

void main() {
  group('the window', () {
    test('is thirty days for a medication that has been there all along', () {
      final report = medAdherence(
        medications: [med(added: day(-400))],
        takesByDay: takes({
          0: {'med_1': MedTake.taken},
          1: {'med_1': MedTake.taken},
        }),
        today: today,
      );

      final line = report.lines.single;
      expect(line.windowDays, AdherenceWindow.reportDays);
      expect(line.takenDays, 2);
      expect(line.unrecordedDays, AdherenceWindow.reportDays - 2);
      expect(line.isShorterThanWindow, isFalse);
    });

    test('starts on the day the medication was added', () {
      // Added three days ago: "taken on 2 of the last 30 days" would be true and
      // would read as a failure. The window is its own.
      final report = medAdherence(
        medications: [med(added: day(-2))],
        takesByDay: takes({
          0: {'med_1': MedTake.taken},
          2: {'med_1': MedTake.taken},
        }),
        today: today,
      );

      final line = report.lines.single;
      expect(line.windowDays, 3);
      expect(line.takenDays, 2);
      expect(line.unrecordedDays, 1);
      expect(line.isShorterThanWindow, isTrue);
      expect(line.sentence, 'In the 3 days since you added it: taken on 2 days, '
          'nothing recorded on 1.');
    });

    test('a medication added today has one day in it, not thirty', () {
      final report = medAdherence(
        medications: [med(added: today)],
        takesByDay: takes({0: {'med_1': MedTake.taken}}),
        today: today,
      );

      expect(report.lines.single.windowDays, 1);
      expect(report.lines.single.takenDays, 1);
    });

    test('a row dated in the future does not count backwards', () {
      final report = medAdherence(
        medications: [med(added: day(5))],
        takesByDay: const {},
        today: today,
      );

      expect(report.lines.single.windowDays, 1);
      expect(report.lines.single.unrecordedDays, 1);
    });

    test('an older row with no added day is counted over the whole window', () {
      final report = medAdherence(
        medications: [med()],
        takesByDay: takes({3: {'med_1': MedTake.taken}}),
        today: today,
      );

      expect(report.lines.single.windowDays, AdherenceWindow.reportDays);
      expect(report.lines.single.takenDays, 1);
    });
  });

  group('the three counts', () {
    test('a day with nothing tapped is unrecorded, never a miss', () {
      final report = medAdherence(
        medications: [med(added: day(-6))],
        takesByDay: takes({
          0: {'med_1': MedTake.taken},
          1: {'med_1': MedTake.skipped},
        }),
        today: today,
      );

      final line = report.lines.single;
      expect(line.windowDays, 7);
      expect(line.takenDays, 1);
      expect(line.skippedDays, 1);
      expect(line.unrecordedDays, 5,
          reason: 'five days nobody tapped are five unrecorded days, not five '
              'missed doses');
      expect(line.recordedDays, 2);
    });

    test('a skip is only ever a tap', () {
      // The distinction the whole feature exists for: a day with no row at all and
      // a day with an explicit skip are different data.
      final silent = medAdherence(
        medications: [med()],
        takesByDay: const {},
        today: today,
      ).lines.single;
      final skipped = medAdherence(
        medications: [med()],
        takesByDay: takes({0: {'med_1': MedTake.skipped}}),
        today: today,
      ).lines.single;

      expect(silent.skippedDays, 0);
      expect(skipped.skippedDays, 1);
      expect(silent.isSilent, isTrue);
      expect(skipped.isSilent, isFalse);
    });

    test('a tap for another medication does not count for this one', () {
      final report = medAdherence(
        medications: [med(id: 'med_1'), med(id: 'med_2', name: 'Metformin')],
        takesByDay: takes({
          0: {'med_1': MedTake.taken},
          1: {'med_2': MedTake.skipped},
        }),
        today: today,
      );

      final first = report.lines.firstWhere((line) => line.medication.id == 'med_1');
      expect(first.takenDays, 1);
      expect(first.skippedDays, 0);
      expect(report.spokenFor, 2);
    });

    test('days outside the window are ignored', () {
      final report = medAdherence(
        medications: [med(added: day(-400))],
        takesByDay: takes({
          31: {'med_1': MedTake.taken},
          0: {'med_1': MedTake.taken},
        }),
        today: today,
      );

      expect(report.lines.single.takenDays, 1);
    });
  });

  group('the words', () {
    test('there is no percentage and no score in anything it says', () {
      final report = medAdherence(
        medications: [med(added: day(-29))],
        takesByDay: takes({
          0: {'med_1': MedTake.taken},
          3: {'med_1': MedTake.skipped},
        }),
        today: today,
      );

      expect(report.summary, isNot(contains('%')));
      expect(report.lines.single.sentence, isNot(contains('%')));
      for (final note in MedAdherenceReport.notes) {
        expect(note, isNot(contains('%')));
      }
      // And the words it does use are counts.
      expect(
        report.lines.single.sentence,
        'In the last 30 days: taken on 1 day, skipped on 1, nothing recorded on 28.',
      );
    });

    test('the summary says how many things it is talking about', () {
      final report = medAdherence(
        medications: [med(id: 'a'), med(id: 'b', name: 'Metformin')],
        takesByDay: takes({
          0: {'a': MedTake.taken},
        }),
        today: today,
      );

      expect(report.summary, '2 things on your list, 1 with something recorded in '
          'the last 30 days.');
    });

    test('a list with nothing recorded says so once', () {
      final report = medAdherence(
        medications: [med()],
        takesByDay: const {},
        today: today,
      );

      expect(report.summary, contains('none with anything recorded'));
      expect(report.lines.single.sentence, contains('no taps either way'));
      expect(report.spokenFor, 0);
    });

    test('an empty list is a sentence, not a blank card', () {
      final report = medAdherence(
        medications: const [],
        takesByDay: const {},
        today: today,
      );

      expect(report.isEmpty, isTrue);
      expect(report.summary, 'No medications or supplements on your list yet.');
    });

    test('the notes name the two rules the counts depend on', () {
      final notes = MedAdherenceReport.notes.join(' ');
      expect(notes, contains('is not a missed day'));
      expect(notes, contains('starts on the day you added'));
      expect(notes, contains('No percentage and no score'));
    });
  });
}
