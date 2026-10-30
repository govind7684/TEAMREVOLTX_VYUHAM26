import '../domain/models/incident.dart';
import 'photo_check.dart';

/// One line in a person's point history.
class CreditEvent {
  const CreditEvent(this.title, this.points, this.at, {this.incidentId});
  final String title;
  final int points;
  final DateTime at;
  final String? incidentId;
}

class CreditSummary {
  const CreditSummary(this.total, this.events);
  final int total;
  final List<CreditEvent> events;

  String get level => Credits.levelFor(total).$1;

  /// Points still needed for the next level, or null at the top level.
  int? get toNext {
    final next = Credits.levels.where((l) => l.$2 > total).firstOrNull;
    return next == null ? null : next.$2 - total;
  }

  String? get nextLevel => Credits.levels.where((l) => l.$2 > total).firstOrNull?.$1;
}

/// Civic credit points for citizens who report problems.
///
/// Points are COUNTED from the person's own reports, not stored, so they cannot
/// be edited on the phone and they agree on every device. Most points come from
/// what staff do with the report (accepting it, resolving it), so reporting
/// nonsense earns almost nothing. Points have no cash value; they are
/// recognition only.
class Credits {
  static const perReport = 10; // a report that staff did not reject
  static const liveBonus = 5; // photo taken live and not flagged
  static const acceptedBonus = 10; // staff took it up
  static const resolvedBonus = 15; // the problem was fixed
  static const confirmedSame = 5; // confirmed to be the same problem someone else reported
  static const feedbackBonus = 3; // told us whether the fix worked
  static const dailyCap = 3; // reports per day that earn the "report" points

  static const levels = <(String, int)>[
    ('Newcomer', 0),
    ('Active citizen', 50),
    ('Community guardian', 150),
    ('City champion', 400),
  ];

  static (String, int) levelFor(int points) =>
      levels.lastWhere((l) => points >= l.$2, orElse: () => levels.first);

  /// [mine] are the person's own reports; [feedbackFor] are the ids of reports
  /// they gave feedback on.
  static CreditSummary compute(List<Incident> mine, {Set<String> feedbackFor = const {}}) {
    final events = <CreditEvent>[];
    final byCreated = [...mine]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final perDay = <String, int>{};
    for (final i in byCreated) {
      final dead = i.status.name == 'rejected' || i.status.name == 'withdrawn';
      if (dead) continue;
      final day = '${i.createdAt.year}-${i.createdAt.month}-${i.createdAt.day}';
      if (i.duplicateOfId != null) {
        if (i.dupVerified || !i.status.isOpen) {
          events.add(CreditEvent('Same problem confirmed', confirmedSame, i.updatedAt, incidentId: i.id));
        }
        continue;
      }
      final used = perDay[day] ?? 0;
      if (used < dailyCap) {
        perDay[day] = used + 1;
        events.add(CreditEvent('Report submitted', perReport, i.createdAt, incidentId: i.id));
        final check = PhotoCheck.parse(i.photoCheck);
        if (i.photoOrigin == 'camera' && check?.verdict != PhotoVerdict.suspicious) {
          events.add(CreditEvent('Live photo', liveBonus, i.createdAt, incidentId: i.id));
        }
      }
      final staffActed = const ['assigned', 'inProgress', 'resolved', 'closed'].contains(i.status.name);
      if (staffActed) {
        events.add(CreditEvent('Accepted by the city', acceptedBonus, i.updatedAt, incidentId: i.id));
      }
      if (i.status.name == 'resolved' || i.status.name == 'closed') {
        events.add(CreditEvent('Problem resolved', resolvedBonus, i.updatedAt, incidentId: i.id));
      }
    }
    for (final id in feedbackFor) {
      final i = mine.where((m) => m.id == id).firstOrNull;
      if (i != null) events.add(CreditEvent('Feedback given', feedbackBonus, i.updatedAt, incidentId: id));
    }
    events.sort((a, b) => b.at.compareTo(a.at));
    return CreditSummary(events.fold(0, (s, e) => s + e.points), events);
  }
}
