// The daily-metric layer: what a typed number means, and what the app promises
// about the numbers it keeps.
//
// The rules tested here are the ones that would otherwise show up as "the app says
// invalid" on someone's phone: a cleared field is not an error, a comma is a
// decimal point, and a value outside the range is refused by naming the range.

import 'package:cystera/core/metrics/metric_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a typed value', () {
    test('a blank field clears the reading rather than failing', () {
      expect(parseMetric(MetricKind.weight, ''), isA<MetricCleared>());
      expect(parseMetric(MetricKind.weight, '   '), isA<MetricCleared>());
    });

    test('a lone comma or dot is still a cleared field', () {
      expect(parseMetric(MetricKind.weight, ','), isA<MetricCleared>());
      expect(parseMetric(MetricKind.weight, '.'), isA<MetricCleared>());
    });

    test('a comma is read as a decimal separator', () {
      final result = parseMetric(MetricKind.weight, '62,4');
      expect(result, isA<MetricAccepted>());
      expect((result as MetricAccepted).value, 62.4);
    });

    test('something that is not a number says exactly that', () {
      final result = parseMetric(MetricKind.weight, 'sixty two');
      expect(result, isA<MetricRejected>());
      expect((result as MetricRejected).reason, 'That is not a number.');
    });

    test('a value below the range is refused with the range named', () {
      final result = parseMetric(MetricKind.weight, '9');
      expect(result, isA<MetricRejected>());
      final reason = (result as MetricRejected).reason;
      expect(reason, contains('20.0'));
      expect(reason, contains('500.0'));
      // The refusal must not be the word "invalid", which says nothing about what
      // would be accepted.
      expect(reason.toLowerCase(), isNot(contains('invalid')));
    });

    test('a value above the range is refused too', () {
      expect(parseMetric(MetricKind.sleep, '30'), isA<MetricRejected>());
    });

    test('the ends of the range are accepted', () {
      expect(parseMetric(MetricKind.weight, '20'), isA<MetricAccepted>());
      expect(parseMetric(MetricKind.weight, '500'), isA<MetricAccepted>());
    });
  });

  group('how a reading is written out', () {
    test('a weight carries its unit to one decimal place', () {
      expect(MetricKind.weight.format(62.44), '62.4 kg');
    });

    test('a count carries no decimals', () {
      expect(MetricKind.water.format(7), '7 glasses');
    });

    test('temperature keeps two decimals, because the second one is the signal', () {
      expect(MetricKind.bbt.format(36.72), '36.72 °C');
    });

    test('cervical mucus is a word, not a score', () {
      expect(MetricKind.mucus.format(1), 'Dry');
      expect(MetricKind.mucus.format(2), 'Sticky');
      expect(MetricKind.mucus.format(3), 'Wet');
      // Nothing about mucus is drawn as a number: a "1–3 mucus score" beside a
      // fertility axis is the reading the app refuses to make.
      expect(MetricKind.mucus.format(3), isNot(contains('3')));
    });

    test('activity appends what was done, when it was named', () {
      const metric = DayMetric(
        kind: MetricKind.exercise,
        value: 30,
        detail: 'Swimming',
      );
      expect(metric.display, '30 minutes · Swimming');
    });

    test('activity without a name is just the minutes', () {
      const metric = DayMetric(kind: MetricKind.exercise, value: 0);
      expect(metric.display, '0 minutes');
      // A rest day is a recorded fact, not a missing one.
      expect(metric.display, isNotEmpty);
    });
  });

  group('which measurements are switched on', () {
    test('nothing is on to begin with', () {
      expect(MetricPrefs.none.ordered, isEmpty);
    });

    test('the drawn order is fixed, so toggling one does not reshuffle the screen',
        () {
      final prefs = MetricPrefs.none
          .withToggled(MetricKind.water, true)
          .withToggled(MetricKind.weight, true);
      expect(prefs.ordered, [MetricKind.weight, MetricKind.water]);
    });

    test('a round trip through JSON keeps exactly the set that was on', () {
      final prefs = MetricPrefs.none
          .withToggled(MetricKind.bbt, true)
          .withToggled(MetricKind.sleep, true);
      final restored = MetricPrefs.decode(prefs.encode());
      expect(restored.enabled, prefs.enabled);
    });

    test('an unreadable prefs blob turns nothing on rather than taking the app down',
        () {
      expect(MetricPrefs.decode('not json at all').enabled, isEmpty);
    });

    test('a stored id that no longer exists is dropped, not counted', () {
      final restored = MetricPrefs.decode('{"enabled":["weight","teleportation"]}');
      expect(restored.enabled, {MetricKind.weight});
    });
  });

  group('the fertility-adjacent pair is marked as such', () {
    test('temperature and mucus are, and nothing else is', () {
      expect(MetricKind.bbt.isFertilityAdjacent, isTrue);
      expect(MetricKind.mucus.isFertilityAdjacent, isTrue);
      for (final kind in [
        MetricKind.weight,
        MetricKind.sleep,
        MetricKind.exercise,
        MetricKind.water,
      ]) {
        expect(kind.isFertilityAdjacent, isFalse, reason: kind.title);
      }
    });
  });

  group('waist and blood pressure', () {
    test('are closed ids, formatted with their units like every other kind', () {
      expect(MetricKind.byId('waist'), MetricKind.waist);
      expect(MetricKind.byId('bp_systolic'), MetricKind.bpSystolic);
      expect(MetricKind.byId('bp_diastolic'), MetricKind.bpDiastolic);
      expect(MetricKind.waist.format(76.5), '76.5 cm');
      expect(MetricKind.bpSystolic.format(118), '118 mmHg');
      expect(MetricKind.bpDiastolic.format(76), '76 mmHg');
      // Measurements, not verdicts, and not fertility-adjacent: neither number
      // carries a category and neither is read as a signal.
      expect(MetricKind.bpSystolic.isFertilityAdjacent, isFalse);
      expect(MetricKind.waist.isFertilityAdjacent, isFalse);
    });

    test('refuse a number no cuff would print, with the range named', () {
      final sys = parseMetric(MetricKind.bpSystolic, '40');
      expect(sys, isA<MetricRejected>());
      expect((sys as MetricRejected).reason, contains('50 to 300 mmHg'));

      final dia = parseMetric(MetricKind.bpDiastolic, '250');
      expect(dia, isA<MetricRejected>());
      expect((dia as MetricRejected).reason, contains('30 to 200 mmHg'));

      final waist = parseMetric(MetricKind.waist, '12');
      expect(waist, isA<MetricRejected>());
      expect((waist as MetricRejected).reason, contains('40.0 to 250.0 cm'));
    });

    test('accept a reading inside the range, comma decimals included', () {
      expect(
        (parseMetric(MetricKind.waist, '76,5') as MetricAccepted).value,
        76.5,
      );
      expect(
        (parseMetric(MetricKind.bpSystolic, '118') as MetricAccepted).value,
        118,
      );
      expect(
        (parseMetric(MetricKind.bpDiastolic, '76') as MetricAccepted).value,
        76,
      );
    });

    test('travel through the switches and draw after the six that came first', () {
      final prefs = MetricPrefs.none
          .withToggled(MetricKind.bpSystolic, true)
          .withToggled(MetricKind.waist, true);
      final restored = MetricPrefs.decode(prefs.encode());
      expect(restored.enabled, {MetricKind.bpSystolic, MetricKind.waist});
      expect(restored.ordered, [MetricKind.waist, MetricKind.bpSystolic],
          reason: 'the drawn order follows the enum, not the toggle order');
    });
  });
}
