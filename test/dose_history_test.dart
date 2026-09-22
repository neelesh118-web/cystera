// The stepped line, as arithmetic — and the words it prints.
//
// doseChart is the only chart logic in the app that runs inside a clinical
// document, so its rules are pinned one claim at a time: nothing before the
// first entry, day-then-id ordering, today as the right edge even when a
// restored clock says otherwise, same wording back to the same height, and
// no zero-width run ever drawn. The entry's own `summary` gets the same
// treatment because the report bullet, the sheet row and the undo sentence
// all render through it — one entry, one wording.

import 'dart:math';

import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/meds/dose_history.dart';
import 'package:flutter_test/flutter_test.dart';

MedDoseEvent event({
  required String id,
  required DateTime day,
  required DoseEventKind kind,
  String? dose,
  String medicationId = 'med_1',
}) =>
    MedDoseEvent(
      id: id,
      medicationId: medicationId,
      day: day,
      kind: kind,
      dose: dose,
    );

// A March whose 20th is "today" for every test in this file.
final today = DateTime(2026, 3, 20);

void main() {
  group('doseChart', () {
    test('no entries is no line at all, and both ends are the report day', () {
      final chart = doseChart(events: const [], today: today);
      expect(chart.steps, isEmpty);
      expect(chart.levels, isEmpty);
      expect(chart.from, DayKey.dayOf(today));
      expect(chart.to, DayKey.dayOf(today));
      expect(chart.bandCount, 1);
      expect(chart.bandLabel(0), 'not taking');
    });

    test('one start draws from its day to the report day, and nothing before',
        () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 1),
            kind: DoseEventKind.started,
            dose: '500 µg',
          ),
        ],
        today: today,
      );
      expect(chart.steps, hasLength(1));
      final run = chart.steps.single;
      expect(run.level, 1);
      expect(run.from, DateTime(2026, 3, 1));
      expect(run.to, DayKey.dayOf(today));
      expect(chart.from, DateTime(2026, 3, 1));
      expect(chart.to, DayKey.dayOf(today));
      expect(chart.levels, ['500 µg']);
      expect(chart.bandLabel(1), '500 µg');
    });

    test('the window starts at the FIRST entry, not the last (axis bug)', () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 1),
            kind: DoseEventKind.started,
            dose: 'A',
          ),
          event(
            id: 'dose_2',
            day: DateTime(2026, 3, 15),
            kind: DoseEventKind.changed,
            dose: 'B',
          ),
        ],
        today: today,
      );
      expect(chart.from, DateTime(2026, 3, 1));
      expect(chart.steps, hasLength(2));
      expect(chart.steps.first.from, DateTime(2026, 3, 1));
      expect(chart.steps.first.to, DateTime(2026, 3, 15));
      expect(chart.steps.last.from, DateTime(2026, 3, 15));
    });

    test('a change splits the run exactly on the day it was dated', () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 5),
            kind: DoseEventKind.started,
            dose: '250 µg',
          ),
          event(
            id: 'dose_2',
            day: DateTime(2026, 3, 10),
            kind: DoseEventKind.changed,
            dose: '500 µg',
          ),
        ],
        today: today,
      );
      expect(chart.steps.map((step) => step.level), [1, 2]);
      // First-write order owns the heights: 250 was written first, so it is
      // the lower band no matter which is the bigger number — the heights
      // are not amounts.
      expect(chart.levels, ['250 µg', '500 µg']);
      expect(chart.bandLabel(1), '250 µg');
      expect(chart.bandLabel(2), '500 µg');
    });

    test('a stop falls to the baseline and the baseline holds to today', () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 2),
            kind: DoseEventKind.started,
            dose: '1000 IU',
          ),
          event(
            id: 'dose_2',
            day: DateTime(2026, 3, 12),
            kind: DoseEventKind.stopped,
          ),
        ],
        today: today,
      );
      expect(chart.steps, hasLength(2));
      expect(chart.steps.last.level, 0);
      expect(chart.steps.last.from, DateTime(2026, 3, 12));
      expect(chart.steps.last.to, DayKey.dayOf(today));
      expect(chart.bandLabel(0), 'not taking');
      // A stop carries no dose — it must not have invented a band for one.
      expect(chart.levels, hasLength(1));
    });

    test('a restart on the same wording returns to ITS height, not a new one',
        () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 1),
            kind: DoseEventKind.started,
            dose: 'A',
          ),
          event(
            id: 'dose_2',
            day: DateTime(2026, 3, 6),
            kind: DoseEventKind.changed,
            dose: 'B',
          ),
          event(
            id: 'dose_3',
            day: DateTime(2026, 3, 11),
            kind: DoseEventKind.stopped,
          ),
          event(
            id: 'dose_4',
            day: DateTime(2026, 3, 16),
            kind: DoseEventKind.started,
            dose: 'A',
          ),
        ],
        today: today,
      );
      expect(chart.levels, ['A', 'B']);
      expect(chart.steps.map((step) => step.level), [1, 2, 0, 1]);
      expect(chart.steps.last.from, DateTime(2026, 3, 16));
    });

    test('two entries one day resolve by id, and the day holds one line only',
        () {
      final chart = doseChart(
        events: [
          // Deliberately listed later than its id order: the day, then the
          // id, is the only order the record holds.
          event(
            id: 'dose_2',
            day: DateTime(2026, 3, 8),
            kind: DoseEventKind.changed,
            dose: 'B',
          ),
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 8),
            kind: DoseEventKind.started,
            dose: 'A',
          ),
        ],
        today: today,
      );
      // The start's run was closed with no width (both entries one day), so
      // only the day's last word holds going forward.
      expect(chart.steps, hasLength(1));
      expect(chart.steps.single.level, 2);
      expect(chart.steps.single.from, DateTime(2026, 3, 8));
      expect(chart.levels, ['A', 'B']);
    });

    test('a change that changes nothing does not split the run', () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 3),
            kind: DoseEventKind.started,
            dose: 'A',
          ),
          event(
            id: 'dose_2',
            day: DateTime(2026, 3, 9),
            kind: DoseEventKind.changed,
            dose: ' A ',
          ),
        ],
        today: today,
      );
      expect(chart.steps, hasLength(1));
      expect(chart.steps.single.from, DateTime(2026, 3, 3));
      expect(chart.steps.single.level, 1);
    });

    test('every entry today draws no line — one date has no width', () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: today,
            kind: DoseEventKind.started,
            dose: 'A',
          ),
        ],
        today: today,
      );
      expect(chart.steps, isEmpty);
      expect(chart.from, DayKey.dayOf(today));
    });

    test('a day from the future is clamped into the report, never past it',
        () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 25),
            kind: DoseEventKind.started,
            dose: 'A',
          ),
        ],
        today: today,
      );
      expect(chart.to, DayKey.dayOf(today));
      for (final step in chart.steps) {
        expect(
          DayKey.dayOf(step.to).isAfter(DayKey.dayOf(today)),
          isFalse,
          reason: 'a run reached past the report day',
        );
      }
      // Clamped onto today itself: no width, so no line.
      expect(chart.steps, isEmpty);
      expect(chart.from, DayKey.dayOf(today));
    });

    test('blank doses share one band, named the way the report names it', () {
      final chart = doseChart(
        events: [
          event(
            id: 'dose_1',
            day: DateTime(2026, 3, 4),
            kind: DoseEventKind.started,
            // no dose written
          ),
          event(
            id: 'dose_2',
            day: DateTime(2026, 3, 9),
            kind: DoseEventKind.changed,
            dose: '   ',
          ),
        ],
        today: today,
      );
      expect(chart.levels, ['']);
      expect(chart.bandCount, 2);
      expect(chart.bandLabel(1), 'no dose written');
      expect(chart.steps, hasLength(1));
    });
  });

  group('MedDoseEvent', () {
    test('summary is the one wording the bullet, the row and the toast share',
        () {
      expect(
        event(
          id: 'd1',
          day: today,
          kind: DoseEventKind.started,
          dose: '500 µg',
        ).summary,
        'started · 500 µg',
      );
      expect(
        event(
          id: 'd2',
          day: today,
          kind: DoseEventKind.changed,
          dose: '  250 µg  ',
        ).summary,
        'changed · 250 µg',
      );
      // A stop names what there is: no dangling separator, no borrowed dose.
      expect(
        event(id: 'd3', day: today, kind: DoseEventKind.stopped).summary,
        'stopped',
      );
      expect(
        event(id: 'd4', day: today, kind: DoseEventKind.started).summary,
        'started · no dose written',
      );
    });

    test('rows round-trip, and anything unreadable drops instead of guessing',
        () {
      final original = event(
        id: 'dose_1',
        day: DateTime(2026, 3, 7),
        kind: DoseEventKind.changed,
        dose: '500 µg',
      );
      final back = MedDoseEvent.fromRow(original.toRow());
      expect(back, isNotNull);
      expect(back!.id, original.id);
      expect(back.day, DayKey.dayOf(original.day));
      expect(back.kind, original.kind);
      expect(back.dose, original.dose);

      expect(
        MedDoseEvent.fromRow({...original.toRow(), 'kind': 'diagnosed'}),
        isNull,
        reason: 'a kind the schema forbids must drop, not become a started',
      );
      expect(
        MedDoseEvent.fromRow({...original.toRow(), 'day': 'whenever'}),
        isNull,
        reason: 'an unparseable day must drop, not become today',
      );
    });

    test('doseLabel tells no dose apart from a dose of whitespace', () {
      expect(event(id: 'a', day: today, kind: DoseEventKind.stopped).doseLabel,
          isNull);
      expect(
        event(
          id: 'b',
          day: today,
          kind: DoseEventKind.changed,
          dose: '  ',
        ).doseLabel,
        isNull,
      );
      expect(
        event(
          id: 'c',
          day: today,
          kind: DoseEventKind.changed,
          dose: ' 500 µg ',
        ).doseLabel,
        '500 µg',
      );
    });

    test('an injected random makes ids reproducible; two calls never collide',
        () {
      final now = DateTime(2026, 3, 20, 9, 30);
      final a = newDoseEventId(now, random: Random(7));
      final b = newDoseEventId(now, random: Random(7));
      expect(a, b, reason: 'same clock, same injected random, same id');
      expect(a, startsWith('dose_'));
      final first = newDoseEventId(now, random: Random(7));
      final second = newDoseEventId(now, random: Random(8));
      expect(first, isNot(second));
    });
  });
}
