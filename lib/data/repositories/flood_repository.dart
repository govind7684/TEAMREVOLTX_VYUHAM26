import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../domain/models/flood.dart';
import '../../domain/models/user.dart';
import '../../services/flood_risk.dart';

/// FloodGuard data. Reading and risk estimates are visible to every signed-in
/// user (they are city-level aggregates). Writing is staff-only and threshold
/// changes are admin-only. Every write is audited.
class FloodRepository {
  FloodRepository(this._db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;
  static const _uuid = Uuid();
  static const _configKey = 'flood_config';

  int get _ts => _now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- reading

  Future<List<RainfallReading>> listReadings({int limit = 30}) async {
    final rows = await _db.query('rainfall_readings',
        orderBy: 'recorded_at DESC', limit: limit);
    return rows.map(RainfallReading.fromMap).toList();
  }

  Future<FloodConfig> getConfig() async {
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: [_configKey], limit: 1);
    if (rows.isEmpty) return const FloodConfig();
    try {
      return FloodConfig.fromJson(
          Map<String, Object?>.from(jsonDecode(rows.first['value'] as String) as Map));
    } catch (_) {
      return const FloodConfig(); // corrupted setting: fall back to defaults
    }
  }

  /// Open flooding / blocked-drain reports created in the last 24 hours.
  /// An aggregate count over all departments, so it does not expose records.
  Future<int> countRecentFloodReports() async {
    final since = _now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    final open = IncidentStatus.values.where((s) => s.isOpen).map((s) => s.name).toList();
    final r = await _db.rawQuery('''
      SELECT COUNT(*) c FROM incidents
      WHERE category IN ('flooding','blockedDrain')
        AND created_at >= ?
        AND status IN (${List.filled(open.length, '?').join(',')})''', [since, ...open]);
    return r.first['c'] as int;
  }

  Future<FloodRiskAssessment> assess() async {
    final now = _now();
    final since = now.subtract(const Duration(hours: 7)).millisecondsSinceEpoch;
    final rows = await _db.query('rainfall_readings',
        where: 'recorded_at >= ?', whereArgs: [since]);
    return FloodRiskEstimator.estimate(
      readings: rows.map(RainfallReading.fromMap),
      recentFloodReports: await countRecentFloodReports(),
      config: await getConfig(),
      now: now,
    );
  }

  // ---------------------------------------------------------------- writing

  void _requireStaff(AppUser u) {
    if (!u.isStaff) {
      throw const PermissionDeniedException('Only municipal staff can record readings.');
    }
  }

  Future<FloodRiskAssessment> addReading({
    required AppUser actor,
    required String stationName,
    required double rainfallMm,
    double? waterLevelCm,
    DateTime? recordedAt,
  }) async {
    _requireStaff(actor);
    final now = _now();
    final at = recordedAt ?? now;
    final errors = <String>[];
    final station = stationName.trim();
    if (station.length < 2 || station.length > 60) {
      errors.add('Station name must be 2 to 60 characters.');
    }
    if (rainfallMm.isNaN || rainfallMm < 0 || rainfallMm > 300) {
      errors.add('Rainfall for one hour must be between 0 and 300 mm.');
    }
    if (waterLevelCm != null && (waterLevelCm.isNaN || waterLevelCm < 0 || waterLevelCm > 1000)) {
      errors.add('Water level must be between 0 and 1000 cm.');
    }
    if (at.isAfter(now.add(const Duration(minutes: 5)))) {
      errors.add('The reading time cannot be in the future.');
    }
    if (now.difference(at) > const Duration(days: 7)) {
      errors.add('Readings older than 7 days are not accepted.');
    }
    if (errors.isNotEmpty) throw ValidationException(errors);

    final before = await assess();
    await _db.transaction((txn) async {
      await _insert(txn, actor, ReadingDraft(station, rainfallMm, waterLevelCm, at),
          ReadingSource.manual);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'flood_reading_added',
        'detail': '$station: ${rainfallMm.toStringAsFixed(1)} mm'
            '${waterLevelCm == null ? '' : ', ${waterLevelCm.toStringAsFixed(0)} cm'}',
        'created_at': _ts,
      });
    });
    return _afterWrite(before, actor);
  }

  /// Removes readings marked simulated by earlier builds. Nothing creates them now.
  Future<void> clearSimulated(AppUser actor) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can clear simulated data.');
    }
    await _db.transaction((txn) async {
      final n = await txn.delete('rainfall_readings', where: "source = 'simulated'");
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'flood_simulated_cleared',
        'detail': 'Removed $n simulated readings',
        'created_at': _ts,
      });
    });
  }

  Future<void> saveConfig(AppUser actor, FloodConfig config) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can change thresholds.');
    }
    final errors = config.validate();
    if (errors.isNotEmpty) throw ValidationException(errors);
    await _db.transaction((txn) async {
      await txn.insert(
        'app_settings',
        {'key': _configKey, 'value': jsonEncode(config.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'flood_thresholds_changed',
        'detail': jsonEncode(config.toJson()),
        'created_at': _ts,
      });
    });
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _insert(DatabaseExecutor txn, AppUser actor, ReadingDraft d, ReadingSource s) {
    return txn.insert('rainfall_readings', {
      'id': _uuid.v4(),
      'station_name': d.stationName,
      'rainfall_mm': d.rainfallMm,
      'water_level_cm': d.waterLevelCm,
      'recorded_at': d.recordedAt.millisecondsSinceEpoch,
      'source': s.name,
      'entered_by': actor.id,
      'is_demo': actor.isDemo ? 1 : 0,
      'created_at': _ts,
    });
  }

  /// Re-estimates after a write. When the level rises to Warning or above,
  /// drainage officers and administrators get an in-app notification.
  Future<FloodRiskAssessment> _afterWrite(FloodRiskAssessment before, AppUser actor) async {
    final after = await assess();
    if (after.level.index >= FloodRiskLevel.warning.index &&
        after.level.index > before.level.index) {
      final targets = await _db.query('users',
          where: "is_active = 1 AND (role = 'admin' OR (role = 'officer' AND department_id = ?))",
          whereArgs: [Departments.drainage]);
      final batch = _db.batch();
      for (final u in targets) {
        batch.insert('notifications', {
          'id': _uuid.v4(),
          'user_id': u['id'],
          'title': 'Flood risk estimate: ${after.level.label}',
          'body': 'Raised by the rule-based estimate'
              '${after.usesSimulatedData ? ' (includes SIMULATED data)' : ''}. '
              'Review FloodGuard and confirm conditions on the ground.',
          'incident_id': null,
          'is_read': 0,
          'created_at': _ts,
        });
      }
      await batch.commit(noResult: true);
    }
    return after;
  }
}
