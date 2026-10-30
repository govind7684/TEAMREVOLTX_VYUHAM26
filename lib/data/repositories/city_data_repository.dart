import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../domain/models/city_update.dart';
import '../../domain/models/user.dart';

/// The city updates board: readings, advisories and alerts that municipal staff
/// type in. Everyone signed in can read it; only staff can write, officers only
/// for their own department's modules, administrators for all. Every write is
/// audited. Rows carry a `source`, so a later automatic importer can add rows
/// without any screen changing.
class CityDataRepository {
  CityDataRepository(this._db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  int get _ts => _now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- reading

  /// Current (not expired) updates, newest first.
  Future<List<CityUpdate>> list({CityModule? module, int limit = 100}) async {
    final rows = await _db.rawQuery('''
      SELECT c.*, u.name AS who
      FROM city_updates c LEFT JOIN users u ON u.id = c.entered_by
      WHERE (c.expires_at IS NULL OR c.expires_at > ?)
        ${module == null ? '' : 'AND c.module = ?'}
      ORDER BY c.created_at DESC
      LIMIT ?''', [_ts, if (module != null) module.name, limit]);
    return rows.map(CityUpdate.fromMap).toList();
  }

  // ---------------------------------------------------------------- writing

  /// Modules this person may post to.
  static List<CityModule> allowedModules(AppUser u) {
    if (u.role == UserRole.admin) return CityModule.values;
    if (u.role == UserRole.officer) {
      return CityModule.values.where((m) => m.departmentId == u.departmentId).toList();
    }
    return const [];
  }

  Future<CityUpdate> add({
    required AppUser actor,
    required CityModule module,
    required UpdateKind kind,
    required String title,
    String? detail,
    String? area,
    double? value,
    String? unit,
    int? validForHours,
  }) async {
    if (!actor.isStaff) {
      throw const PermissionDeniedException('Only municipal staff can post city updates.');
    }
    if (!allowedModules(actor).contains(module)) {
      throw const PermissionDeniedException(
          'Your department can only post updates for its own services.');
    }
    final t = title.trim();
    final d = detail?.trim() ?? '';
    final a = area?.trim() ?? '';
    final u = unit?.trim() ?? '';
    final errors = <String>[];
    if (t.length < 3 || t.length > 80) errors.add('Title must be 3 to 80 characters.');
    if (d.length > 500) errors.add('Details must be 500 characters or fewer.');
    if (a.length > 60) errors.add('Area must be 60 characters or fewer.');
    if (u.length > 12) errors.add('Unit must be 12 characters or fewer.');
    if (value != null && (value.isNaN || value.isInfinite || value.abs() > 1000000)) {
      errors.add('The value is not a sensible number.');
    }
    if (value != null && u.isEmpty) errors.add('Add a unit for the value (for example mm or cm).');
    if (value == null && u.isNotEmpty) errors.add('Enter the value that goes with the unit.');
    if (validForHours != null && (validForHours < 1 || validForHours > 24 * 90)) {
      errors.add('Validity must be between 1 hour and 90 days.');
    }
    if (errors.isNotEmpty) throw ValidationException(errors);

    final id = _uuid.v4();
    final now = _ts;
    await _db.transaction((txn) async {
      await txn.insert('city_updates', {
        'id': id,
        'module': module.name,
        'kind': kind.name,
        'title': t,
        'detail': d.isEmpty ? null : d,
        'area': a.isEmpty ? null : a,
        'value': value,
        'unit': u.isEmpty ? null : u,
        'source': UpdateSource.manual.name,
        'entered_by': actor.id,
        'is_demo': actor.isDemo ? 1 : 0,
        'created_at': now,
        'expires_at': validForHours == null ? null : now + validForHours * 3600 * 1000,
      });
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'city_update_posted',
        'detail': '${module.label} ${kind.label}: $t',
        'created_at': now,
      });
      if (kind == UpdateKind.alert) {
        final people = await txn.query('users',
            columns: ['id'], where: 'is_active = 1 AND id != ?', whereArgs: [actor.id]);
        final batch = txn.batch();
        for (final p in people) {
          batch.insert('notifications', {
            'id': _uuid.v4(),
            'user_id': p['id'],
            'title': 'City alert: $t',
            'body': '${module.label}${a.isEmpty ? '' : ' · $a'}. Open City updates for details.',
            'incident_id': null,
            'is_read': 0,
            'created_at': now,
          });
        }
        await batch.commit(noResult: true);
      }
    });
    return (await list(limit: 500)).firstWhere((x) => x.id == id);
  }

  /// Administrators can remove any update; staff can remove their own.
  Future<void> remove(AppUser actor, String id) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('city_updates', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw const NotFoundException();
      final owner = rows.first['entered_by'] as String;
      if (actor.role != UserRole.admin && !(actor.isStaff && owner == actor.id)) {
        throw const PermissionDeniedException('You can only remove your own updates.');
      }
      await txn.delete('city_updates', where: 'id = ?', whereArgs: [id]);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'city_update_removed',
        'detail': 'Removed "${rows.first['title']}"',
        'created_at': _ts,
      });
    });
  }
}
