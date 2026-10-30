import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/enums.dart';
import '../domain/models/user.dart';
import 'cloud_store.dart';

/// Shares reports between phones through the cloud database (Firestore, free
/// plan). The phone's own SQLite stays the working copy; this copies changes
/// up and down.
///
/// How it works, and where it is simple on purpose:
///  * Each report is ONE cloud document: the report row plus its history,
///    assignments, supporters and feedback. Staff-only notes and resource
///    requests go in a separate staff-only document.
///  * A change is detected by hashing the document. Something that differs from
///    what was last synced is uploaded; a document that arrives is written into
///    the local database and its hash remembered, so it is not sent back.
///  * Conflicts: reports only grow, so two copies are MERGED: history, notes,
///    assignments, supporters and requests from both phones are combined; a
///    record on both sides keeps its further-along version; plain fields
///    (status, priority, ...) come from the copy with the newer `updated_at`.
///    City updates and services are simple last-write-wins.
///  * Photos and the Document Vault never leave the phone.
class SyncService {
  SyncService(this._db, this._store, this._user, {this.onChange});
  final Database _db;
  final CloudStore _store;
  final AppUser _user;

  /// Called after documents from other phones were written locally.
  final Future<void> Function()? onChange;

  final _subs = <StreamSubscription<List<RemoteDoc>>>[];
  Timer? _timer, _debounce;
  bool _pushing = false, _stopped = false;
  final _colCache = <String, Set<String>>{};

  /// Last problem seen (for a status line); null when fine.
  String? lastError;

  // ------------------------------------------------------------------ start

  void start() {
    final u = _user;
    final String? incField;
    final Object? incEquals;
    switch (u.role) {
      case UserRole.citizen:
        incField = 'reporter_id';
        incEquals = u.id;
      case UserRole.officer:
        incField = 'department_id';
        incEquals = u.departmentId ?? '-';
      case UserRole.admin:
        incField = null;
        incEquals = null;
    }
    _listen('incidents', _applyIncident, field: incField, equals: incEquals);
    if (u.isStaff) {
      _listen('incident_staff', _applyStaff, field: incField, equals: incEquals);
    }
    _listen('notifications', _applyNotification, field: 'user_id', equals: u.id);
    _listen('city_updates', (d) => _applyRow('city_updates', d, ['entered_by']));
    _listen('service_places', (d) => _applyRow('service_places', d, ['added_by']));
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => push());
    push();
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _debounce?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  /// Upload soon (after a local change). Several calls in a row make one upload.
  void pushSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), push);
  }

  void _listen(String collection, Future<bool> Function(RemoteDoc) apply,
      {String? field, Object? equals}) {
    _subs.add(_store.watch(collection, field: field, equals: equals).listen((docs) async {
      var changed = false;
      for (final d in docs) {
        try {
          if (await apply(d)) changed = true;
        } catch (e) {
          lastError = 'Could not apply $collection/${d.id}: $e';
        }
      }
      if (changed && !_stopped) await onChange?.call();
    }, onError: (Object e) {
      lastError = '$collection: $e';
    }));
  }

  // ---------------------------------------------------------------- helpers

  static Object? _canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canon(v[k])};
    }
    if (v is List) return v.map(_canon).toList();
    return v;
  }

  /// The 'people' name list is only there to create stand-in users, so it is
  /// not part of what counts as a change.
  static String _hash(Map<String, Object?> doc) {
    final d = {...doc}..remove('people');
    return sha1.convert(utf8.encode(jsonEncode(_canon(d)))).toString();
  }

  Future<String?> _stored(String key) async {
    final r = await _db.query('sync_state', where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['hash'] as String;
  }

  Future<void> _remember(DatabaseExecutor db, String key, String hash) => db.insert(
      'sync_state', {'key': key, 'hash': hash},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final cached = _colCache[table];
    if (cached != null) return cached;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return _colCache[table] = {for (final r in info) r['name'] as String};
  }

  Map<String, Object?> _only(Map<String, Object?> src, Set<String> cols, {Set<String> skip = const {}}) =>
      {for (final e in src.entries) if (cols.contains(e.key) && !skip.contains(e.key)) e.key: e.value};

  /// {uid: {name, role, department_id}} for every user a document mentions.
  Future<Map<String, Object?>> _people(Iterable<Object?> ids) async {
    final wanted = ids.whereType<String>().toSet();
    if (wanted.isEmpty) return {};
    final marks = List.filled(wanted.length, '?').join(',');
    final rows = await _db.rawQuery(
        'SELECT id, name, role, department_id FROM users WHERE id IN ($marks)', wanted.toList());
    return {
      for (final r in rows)
        r['id'] as String: {
          'name': r['name'],
          'role': r['role'],
          'department_id': r['department_id'],
        }
    };
  }

  /// Makes sure every person a document mentions exists locally (foreign keys).
  /// A real account is never overwritten; a stand-in has no usable password.
  Future<void> _ensureUsers(DatabaseExecutor txn, Object? people, Iterable<Object?> ids) async {
    final map = people is Map ? people : const {};
    for (final id in ids.whereType<String>().toSet()) {
      final have = await txn.query('users', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (have.isNotEmpty) continue;
      final p = map[id] is Map ? map[id] as Map : const {};
      final role = ['citizen', 'officer', 'admin'].contains(p['role']) ? p['role'] : 'citizen';
      String? dept = p['department_id'] as String?;
      if (dept != null) {
        final d = await txn.query('departments', columns: ['id'], where: 'id = ?', whereArgs: [dept], limit: 1);
        if (d.isEmpty) dept = null;
      }
      await txn.insert('users', {
        'id': id,
        'name': (p['name'] as String?)?.trim().isNotEmpty == true ? p['name'] : 'User',
        'email': '$id@cloud.invalid',
        'password_hash': 'cloud-stand-in',
        'salt': '',
        'role': role,
        'department_id': dept,
        'is_demo': 0,
        'is_active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  // ------------------------------------------------------------------- push

  bool _mine(Map<String, Object?> inc) {
    switch (_user.role) {
      case UserRole.citizen:
        return inc['reporter_id'] == _user.id;
      case UserRole.officer:
        return inc['department_id'] == _user.departmentId;
      case UserRole.admin:
        return true;
    }
  }

  Future<List<Map<String, Object?>>> _rows(String sql, List<Object?> args) async {
    final r = await _db.rawQuery(sql, args);
    return [for (final m in r) {...m}];
  }

  Future<Map<String, Object?>?> _incidentDoc(String id) async {
    final r = await _db.query('incidents', where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    final inc = {...r.first}..remove('photo_path');
    if (inc['duplicate_of_id'] == null) {
      // The main report this one is linked to never reached this phone, so the
      // local copy has no link. Keep the link the cloud has, or an upload from
      // here would silently remove it.
      final remembered = await _stored('dup:$id');
      if (remembered != null) inc['duplicate_of_id'] = remembered;
    }
    final history = await _rows(
        'SELECT status, actor_id, note, created_at FROM status_history WHERE incident_id = ? ORDER BY id', [id]);
    final assigns = await _rows('SELECT * FROM assignments WHERE incident_id = ? ORDER BY created_at, id', [id]);
    final supporters = await _rows('SELECT * FROM incident_supporters WHERE incident_id = ? ORDER BY user_id', [id]);
    final feedback = await _rows('SELECT * FROM feedback WHERE incident_id = ?', [id]);
    final ids = <Object?>[
      inc['reporter_id'],
      inc['assigned_officer_id'],
      for (final h in history) h['actor_id'],
      for (final a in assigns) ...[a['officer_id'], a['assigned_by']],
      for (final s in supporters) s['user_id'],
      for (final f in feedback) f['user_id'],
    ];
    return {
      ...inc,
      'history': history,
      'assignments': assigns,
      'supporters': supporters,
      'feedback': feedback,
      'people': await _people(ids),
    };
  }

  Future<Map<String, Object?>?> _staffDoc(String id, String? dept) async {
    final notes = await _rows('SELECT * FROM internal_notes WHERE incident_id = ? ORDER BY created_at, id', [id]);
    final reqs = await _rows('SELECT * FROM resource_requests WHERE incident_id = ? ORDER BY created_at, id', [id]);
    if (notes.isEmpty && reqs.isEmpty) return null;
    return {
      'incident_id': id,
      'department_id': dept,
      'notes': notes,
      'requests': reqs,
      'people': await _people([
        for (final n in notes) n['author_id'],
        for (final r in reqs) r['requested_by'],
      ]),
    };
  }

  /// Uploads whatever changed locally since it was last synced.
  Future<void> push() async {
    if (_pushing || _stopped) return;
    _pushing = true;
    try {
      final incs = await _db.query('incidents', columns: ['id', 'reporter_id', 'department_id']);
      for (final i in incs.where(_mine)) {
        final id = i['id'] as String;
        await _pushDoc('incidents', id, 'inc:$id', () => _incidentDoc(id));
        if (_user.isStaff) {
          await _pushDoc('incident_staff', id, 'stf:$id',
              () => _staffDoc(id, i['department_id'] as String?));
        }
      }
      final notes = await _db.query('notifications', orderBy: 'created_at DESC', limit: 300);
      for (final n in notes) {
        final id = n['id'] as String;
        await _pushDoc('notifications', id, 'ntf:$id', () async => {...n});
      }
      if (_user.isStaff) {
        await _pushTable('city_updates', 'entered_by');
      }
      if (_user.canManageServices) {
        await _pushTable('service_places', 'added_by');
      }
      lastError = null;
    } catch (e) {
      lastError = '$e';
    } finally {
      _pushing = false;
    }
  }

  Future<void> _pushTable(String table, String userCol) async {
    final rows = await _db.query(table);
    for (final r in rows) {
      final id = r['id'] as String;
      await _pushDoc(table, id, '$table:$id', () async => {
            ...r,
            'people': await _people([r[userCol]]),
          });
    }
  }

  Future<void> _pushDoc(String collection, String id, String key,
      Future<Map<String, Object?>?> Function() build) async {
    final doc = await build();
    if (doc == null) return;
    final h = _hash(doc);
    if (await _stored(key) == h) return;
    try {
      await _store.put(collection, id, doc);
      await _remember(_db, key, h);
    } catch (e) {
      lastError = '$collection/$id: $e';
    }
  }

  // ------------------------------------------------------------------ apply

  /// True when this phone changed [key]'s document after the last sync and is
  /// newer than the incoming one, so the incoming copy must not overwrite it.
  Future<bool> _localIsNewer(String key, Map<String, Object?>? local, Object? remoteUpdated) async {
    if (local == null) return false;
    final stored = await _stored(key);
    if (stored == null || stored == _hash(local)) return false; // nothing unsynced
    final lu = local['updated_at'] is int ? local['updated_at'] as int : 0;
    final ru = remoteUpdated is int ? remoteUpdated : 0;
    return lu > ru;
  }

  // ---- merging two copies of one report ---------------------------------
  //
  // Reports only ever grow (history, notes, assignments), so two phones that
  // changed the same report offline are merged instead of one overwriting the
  // other: lists are combined by identity; a record that exists on both sides
  // keeps its further-along version; plain fields (status, priority, ...) come
  // from the copy with the newer `updated_at`.

  List<Map<String, Object?>> _union(
    Object? a,
    Object? b,
    String Function(Map<String, Object?>) key, {
    Map<String, Object?> Function(Map<String, Object?> x, Map<String, Object?> y)? pick,
    int Function(Map<String, Object?>, Map<String, Object?>)? order,
  }) {
    final out = <String, Map<String, Object?>>{};
    for (final m in [..._list(a), ..._list(b)]) {
      final k = key(m);
      final have = out[k];
      out[k] = have == null ? m : (pick == null ? have : pick(have, m));
    }
    final list = out.values.toList();
    if (order != null) list.sort(order);
    return list;
  }

  int _n(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

  /// The record that has progressed further: one that was answered/decided
  /// (non-null `responded_at` / `decided_at`) beats one that was not.
  Map<String, Object?> _furtherAlong(Map<String, Object?> x, Map<String, Object?> y, String field) {
    final fx = x[field], fy = y[field];
    if (fx == null && fy != null) return y;
    if (fy == null && fx != null) return x;
    return _n(fy) > _n(fx) ? y : x;
  }

  Map<String, Object?> _mergeIncident(Map<String, Object?>? local, Map<String, Object?> remote) {
    if (local == null) return remote;
    final newer = _n(remote['updated_at']) >= _n(local['updated_at']) ? remote : local;
    final other = identical(newer, remote) ? local : remote;
    return {
      ...other,
      ...newer,
      'history': _union(local['history'], remote['history'],
          (h) => '${h['created_at']}|${h['actor_id']}|${h['status']}|${h['note']}',
          order: (x, y) => _n(x['created_at']).compareTo(_n(y['created_at']))),
      'assignments': _union(local['assignments'], remote['assignments'], (a) => '${a['id']}',
          pick: (x, y) => _furtherAlong(x, y, 'responded_at'),
          order: (x, y) => _n(x['created_at']).compareTo(_n(y['created_at']))),
      'supporters': _union(local['supporters'], remote['supporters'], (s) => '${s['user_id']}'),
      'feedback': _union(local['feedback'], remote['feedback'], (f) => '${f['id']}',
          pick: (x, y) => _n(y['created_at']) > _n(x['created_at']) ? y : x),
      'people': {
        ...(local['people'] is Map ? local['people'] as Map : const {}),
        ...(remote['people'] is Map ? remote['people'] as Map : const {}),
      },
    };
  }

  Future<bool> _applyIncident(RemoteDoc d) async {
    final id = d.id;
    final remote = d.data;
    final local = await _incidentDoc(id);
    if (local != null && _hash(local) == _hash(_normalise(remote, local))) return false;
    final doc = _mergeIncident(local, remote);

    await _db.transaction((txn) async {
      final incCols = await _columns(txn, 'incidents');
      final row = _only(doc, incCols, skip: {'photo_path'});
      final history = _list(doc['history']);
      final assigns = _list(doc['assignments']);
      final supporters = _list(doc['supporters']);
      final feedback = _list(doc['feedback']);

      await _ensureUsers(txn, doc['people'], [
        row['reporter_id'],
        row['assigned_officer_id'],
        for (final h in history) h['actor_id'],
        for (final a in assigns) ...[a['officer_id'], a['assigned_by']],
        for (final s in supporters) s['user_id'],
        for (final f in feedback) f['user_id'],
      ]);

      // A department added on another phone may not exist here yet.
      final dept = row['department_id'];
      if (dept is String) {
        final have = await txn.query('departments', columns: ['id'], where: 'id = ?', whereArgs: [dept], limit: 1);
        if (have.isEmpty) {
          await txn.insert('departments', {'id': dept, 'name': Departments.nameOf(dept)});
        }
      }
      // A main report this phone never received cannot be referenced; remember
      // the link so it is not lost on the next upload.
      final parent = row['duplicate_of_id'];
      var missingParent = false;
      if (parent is String) {
        final p = await txn.query('incidents', columns: ['id'], where: 'id = ?', whereArgs: [parent], limit: 1);
        if (p.isEmpty) {
          row['duplicate_of_id'] = null;
          missingParent = true;
        }
      }
      if (missingParent) {
        await _remember(txn, 'dup:$id', parent as String);
      } else {
        await txn.delete('sync_state', where: 'key = ?', whereArgs: ['dup:$id']);
      }
      final n = await txn.update('incidents', {...row}..remove('id'), where: 'id = ?', whereArgs: [id]);
      if (n == 0) await txn.insert('incidents', {...row, 'id': id});

      await txn.delete('status_history', where: 'incident_id = ?', whereArgs: [id]);
      for (final h in history) {
        await txn.insert('status_history', {
          'incident_id': id,
          'status': h['status'],
          'actor_id': h['actor_id'],
          'note': h['note'],
          'created_at': h['created_at'],
        });
      }
      Future<void> replace(String table, List<Map<String, Object?>> rows) async {
        final cols = await _columns(txn, table);
        await txn.delete(table, where: 'incident_id = ?', whereArgs: [id]);
        for (final r in rows) {
          await txn.insert(table, {..._only(r, cols), 'incident_id': id});
        }
      }

      await replace('assignments', assigns);
      await replace('incident_supporters', supporters);
      await replace('feedback', feedback);
    });
    final after = await _incidentDoc(id);
    // If the merge produced something the cloud does not have yet, leave it
    // un-remembered so the next upload sends it.
    if (after != null && _hash(after) == _hash(_normalise(remote, after))) {
      await _remember(_db, 'inc:$id', _hash(after));
    }
    return true;
  }

  Future<bool> _applyStaff(RemoteDoc d) async {
    final id = d.data['incident_id'] as String? ?? d.id;
    final exists = await _db.query('incidents', columns: ['id', 'department_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (exists.isEmpty) return false; // the report itself has not arrived yet
    final dept = exists.first['department_id'] as String?;
    final local = await _staffDoc(id, dept);
    if (local != null && _hash(local) == _hash(_normalise(d.data, local))) return false;
    final notes = _union(local?['notes'], d.data['notes'], (n) => '${n['id']}',
        order: (x, y) => _n(x['created_at']).compareTo(_n(y['created_at'])));
    final reqs = _union(local?['requests'], d.data['requests'], (r) => '${r['id']}',
        pick: (x, y) => _furtherAlong(x, y, 'decided_at'),
        order: (x, y) => _n(x['created_at']).compareTo(_n(y['created_at'])));
    await _db.transaction((txn) async {
      await _ensureUsers(txn, d.data['people'], [
        for (final n in notes) n['author_id'],
        for (final r in reqs) r['requested_by'],
      ]);
      Future<void> replace(String table, List<Map<String, Object?>> rows) async {
        final cols = await _columns(txn, table);
        await txn.delete(table, where: 'incident_id = ?', whereArgs: [id]);
        for (final r in rows) {
          await txn.insert(table, {..._only(r, cols), 'incident_id': id});
        }
      }

      await replace('internal_notes', notes);
      await replace('resource_requests', reqs);
    });
    final after = await _staffDoc(id, dept);
    if (after != null && _hash(after) == _hash(_normalise(d.data, after))) {
      await _remember(_db, 'stf:$id', _hash(after));
    }
    return true;
  }

  Future<bool> _applyNotification(RemoteDoc d) async {
    final cols = await _columns(_db, 'notifications');
    final row = _only(d.data, cols)..['id'] = d.id;
    final existing = await _db.query('notifications', where: 'id = ?', whereArgs: [d.id], limit: 1);
    if (existing.isNotEmpty && _hash({...existing.first}) == _hash(_normalise(d.data, {...existing.first}))) {
      return false;
    }
    if (row['user_id'] != _user.id) return false;
    final inc = row['incident_id'];
    if (inc is String) {
      final p = await _db.query('incidents', columns: ['id'], where: 'id = ?', whereArgs: [inc], limit: 1);
      if (p.isEmpty) row['incident_id'] = null;
    }
    // A read flag set on this phone is not undone by an older copy.
    if (existing.isNotEmpty && existing.first['is_read'] == 1) row['is_read'] = 1;
    await _db.insert('notifications', row, conflictAlgorithm: ConflictAlgorithm.replace);
    final after = await _db.query('notifications', where: 'id = ?', whereArgs: [d.id]);
    await _remember(_db, 'ntf:${d.id}', _hash({...after.first}));
    return true;
  }

  Future<bool> _applyRow(String table, RemoteDoc d, List<String> userCols) async {
    final cols = await _columns(_db, table);
    final row = _only(d.data, cols)..['id'] = d.id;
    final existing = await _db.query(table, where: 'id = ?', whereArgs: [d.id], limit: 1);
    if (existing.isNotEmpty) {
      final local = {...existing.first, 'people': await _people([existing.first[userCols.first]])};
      if (_hash(local) == _hash(_normalise(d.data, local))) return false;
      if (await _localIsNewer('$table:${d.id}', local, d.data['updated_at'])) return false;
    }
    await _db.transaction((txn) async {
      await _ensureUsers(txn, d.data['people'], [for (final c in userCols) row[c]]);
      final n = await txn.update(table, {...row}..remove('id'), where: 'id = ?', whereArgs: [d.id]);
      if (n == 0) await txn.insert(table, row);
    });
    final after = await _db.query(table, where: 'id = ?', whereArgs: [d.id]);
    await _remember(_db, '$table:${d.id}', _hash({
      ...after.first,
      'people': await _people([after.first[userCols.first]]),
    }));
    return true;
  }

  /// Compares fairly: the remote document may hold only some of the local keys
  /// (or the reverse), so keep the local key set.
  Map<String, Object?> _normalise(Map<String, Object?> remote, Map<String, Object?> like) =>
      {for (final k in like.keys) k: remote[k]};

  List<Map<String, Object?>> _list(Object? v) => v is List
      ? [for (final e in v) if (e is Map) Map<String, Object?>.from(e)]
      : const [];
}
