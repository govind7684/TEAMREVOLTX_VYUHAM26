import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// One document read from the cloud.
class RemoteDoc {
  const RemoteDoc(this.id, this.data);
  final String id;
  final Map<String, Object?> data;
}

/// The two cloud database operations the sync needs. An interface so the sync
/// logic can be tested without Firebase.
abstract class CloudStore {
  Future<void> put(String collection, String id, Map<String, Object?> data);

  /// Emits the documents that were added or changed, first all current ones,
  /// then each later change. [field] / [equals] restrict what is listened to
  /// (the security rules require citizens and officers to ask only for what
  /// they may read).
  Stream<List<RemoteDoc>> watch(String collection, {String? field, Object? equals});
}

class FirestoreStore implements CloudStore {
  FirestoreStore() : _fs = FirebaseFirestore.instance;
  final FirebaseFirestore _fs;

  @override
  Future<void> put(String collection, String id, Map<String, Object?> data) =>
      _fs.collection(collection).doc(id).set(data).timeout(const Duration(seconds: 15));

  @override
  Stream<List<RemoteDoc>> watch(String collection, {String? field, Object? equals}) {
    Query<Map<String, dynamic>> q = _fs.collection(collection);
    if (field != null) q = q.where(field, isEqualTo: equals);
    return q.snapshots().map((snap) => [
          for (final c in snap.docChanges)
            if (c.type != DocumentChangeType.removed && c.doc.data() != null)
              RemoteDoc(c.doc.id, Map<String, Object?>.from(c.doc.data()!)),
        ]);
  }
}
