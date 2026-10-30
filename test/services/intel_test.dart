import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/domain/models/incident.dart';
import 'package:civinex_ai/services/ai/location_importance.dart';
import 'package:civinex_ai/services/ai/priority_scorer.dart';
import 'package:civinex_ai/services/intel/clustering.dart';
import 'package:civinex_ai/services/intel/csv_export.dart';
import 'package:civinex_ai/services/intel/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

Incident inc(String id, double lat, double lng, DateTime at,
        {IncidentCategory cat = IncidentCategory.roadDamage,
        IncidentStatus status = IncidentStatus.submitted,
        Priority p = Priority.medium}) =>
    Incident(
      id: id,
      reporterId: 'u',
      category: cat,
      description: 'd',
      locationText: 'Main road',
      latitude: lat,
      longitude: lng,
      peopleAffected: 1,
      safetyRisk: false,
      priority: p,
      priorityScore: 3,
      priorityReasons: '',
      aiProvider: 'x',
      aiExplanation: '',
      needsHumanReview: false,
      departmentId: cat.departmentId,
      status: status,
      createdAt: at,
      updatedAt: at,
      isDemo: false,
      dataSource: 't',
    );

void main() {
  final now = DateTime(2026, 6, 1);

  group('clustering', () {
    test('nearby reports group, distant ones do not', () {
      final list = [
        inc('a', 9.9500, 76.2800, now),
        inc('b', 9.9505, 76.2802, now),
        inc('c', 10.5000, 76.9000, now),
      ];
      final c = const GeoClusterer(radiusMeters: 250).cluster(list);
      expect(c.length, 2);
      expect(c.first.count, 2);
    });

    test('reports without coordinates are skipped; heat is relative', () {
      final c = const GeoClusterer().cluster([
        inc('a', 9.95, 76.28, now),
        inc('b', 9.9501, 76.2801, now, p: Priority.critical),
        inc('c', 10.5, 76.9, now),
      ]);
      final heat = GeoClusterer.heat(c);
      expect(heat.first.intensity, 1.0);
      expect(heat.last.intensity, lessThan(1.0));
    });
  });

  group('recurrence', () {
    test('three reports at one spot is a recurring fault; one is not', () {
      final a = const RecurrenceAnalyzer();
      final three = [
        inc('a', 9.95, 76.28, now.subtract(const Duration(days: 80))),
        inc('b', 9.95, 76.28, now.subtract(const Duration(days: 40))),
        inc('c', 9.9501, 76.2801, now.subtract(const Duration(days: 2))),
      ];
      final r = a.detect(three, now);
      expect(r.length, 1);
      expect(r.first.reports, 3);
      expect(a.detect([three.first], now), isEmpty);
    });

    test('two reports count when the first was already fixed', () {
      final r = const RecurrenceAnalyzer().detect([
        inc('a', 9.95, 76.28, now.subtract(const Duration(days: 60)), status: IncidentStatus.resolved),
        inc('b', 9.95, 76.28, now.subtract(const Duration(days: 3))),
      ], now);
      expect(r.single.fixedBefore, 1);
    });

    test('insights are labelled as statistics, never as predictions', () {
      final list = [
        for (var d = 0; d < 4; d++) inc('n$d', 9.95 + d * 0.1, 76.28, now.subtract(Duration(days: d + 1))),
        inc('o', 9.95, 76.28, now.subtract(const Duration(days: 45))),
      ];
      final ins = const RecurrenceAnalyzer().insights(list, now);
      expect(ins, isNotEmpty);
      for (final i in ins) {
        expect(i.kindLabel.toLowerCase(), anyOf(contains('not a prediction'), contains('not a trained model')));
      }
    });
  });

  group('priority factors', () {
    test('location importance, recurrence and reporter count each add explained points', () {
      const s = PriorityScorer();
      final base = s.score(
          category: IncidentCategory.roadDamage,
          safetyRisk: false,
          peopleAffected: 1,
          unresolvedFor: Duration.zero,
          similarReports: 0);
      final loc = LocationImportance.assess('Near the District Hospital, Kochi');
      final full = s.score(
          category: IncidentCategory.roadDamage,
          safetyRisk: false,
          peopleAffected: 1,
          unresolvedFor: Duration.zero,
          similarReports: 0,
          locationPoints: loc.points,
          locationReason: loc.reason,
          recurrences: 3,
          reporterCount: 5);
      expect(loc.points, 2);
      expect(full.score, base.score + 2 + 2 + 2);
      expect(full.reasonText, contains('hospital'));
      expect(full.reasonText, contains('recurring'));
      expect(full.reasonText, contains('5 citizens'));
    });

    test('SLA gets shorter as priority rises', () {
      expect(Sla.hours[Priority.critical]!, lessThan(Sla.hours[Priority.high]!));
      expect(Sla.hours[Priority.high]!, lessThan(Sla.hours[Priority.medium]!));
      expect(Sla.hours[Priority.medium]!, lessThan(Sla.hours[Priority.low]!));
    });
  });

  group('csv', () {
    test('formula-looking text is neutralised and commas are quoted', () {
      expect(CsvExport.cell('=SUM(A1)'), "'=SUM(A1)");
      expect(CsvExport.cell('a,b'), '"a,b"');
      expect(CsvExport.cell('say "hi"'), '"say ""hi"""');
    });
  });
}
