import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/models/service_place.dart';
import '../../domain/models/user.dart';

/// Places entered by staff (officers an administrator allotted, and
/// administrators). Anyone signed in can read; only those who may manage
/// services can change them.
class ServicePlacesRepository {
  ServicePlacesRepository(this._db);
  final Database _db;
  static const _uuid = Uuid();

  int get _ts => DateTime.now().millisecondsSinceEpoch;

  void _canManage(AppUser u) {
    if (!u.canManageServices) {
      throw const PermissionDeniedException(
          'Only administrators and officers allotted services access can change this.');
    }
  }

  /// Staff-entered places in [city] (case-insensitive contains), optionally one kind.
  Future<List<ServicePlace>> inCity(String city, {ServiceKind? kind}) async {
    final c = city.trim().toLowerCase();
    final where = ['removed = 0', if (c.isNotEmpty) 'LOWER(city) LIKE ?', if (kind != null) 'kind = ?'];
    final rows = await _db.query('service_places',
        where: where.join(' AND '),
        whereArgs: [if (c.isNotEmpty) '%$c%', if (kind != null) kind.name],
        orderBy: 'kind, name');
    return rows.map(ServicePlace.fromMap).toList();
  }

  Future<List<ServicePlace>> all() async => (await _db.query('service_places',
          where: 'removed = 0', orderBy: 'city, kind, name'))
      .map(ServicePlace.fromMap)
      .toList();

  List<String> _errors(String name, String city, String? phone) => [
        if (name.trim().length < 2) 'Enter the name of the place.',
        if (city.trim().length < 2) 'Enter the city or town.',
        if (phone != null && phone.trim().isNotEmpty && !RegExp(r'^[0-9+\-\s()]{6,20}$').hasMatch(phone.trim()))
          'Enter a valid phone number.',
      ];

  Future<void> save({
    required AppUser actor,
    String? id,
    required String name,
    required ServiceKind kind,
    required String city,
    String? phone,
    String? address,
    String? hours,
    double? latitude,
    double? longitude,
  }) async {
    _canManage(actor);
    final errors = _errors(name, city, phone);
    if (errors.isNotEmpty) throw ValidationException(errors);
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    final values = {
      'name': name.trim(),
      'kind': kind.name,
      'city': city.trim(),
      'phone': clean(phone),
      'address': clean(address),
      'hours': clean(hours),
      'latitude': latitude,
      'longitude': longitude,
      'updated_at': _ts,
    };
    await _db.transaction((txn) async {
      if (id == null) {
        await txn.insert('service_places',
            {'id': _uuid.v4(), ...values, 'added_by': actor.id, 'created_at': _ts});
      } else {
        final n = await txn.update('service_places', values, where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw const NotFoundException();
      }
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': id == null ? 'service_added' : 'service_edited',
        'detail': '${name.trim()} (${kind.label}, ${city.trim()})',
        'created_at': _ts,
      });
    });
  }

  Future<void> delete({required AppUser actor, required String id}) async {
    _canManage(actor);
    await _db.transaction((txn) async {
      // Marked removed (not deleted) so the removal also reaches the other phones.
      await txn.update('service_places', {'removed': 1, 'updated_at': _ts},
          where: 'id = ?', whereArgs: [id]);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'service_removed',
        'detail': id,
        'created_at': _ts,
      });
    });
  }
}
