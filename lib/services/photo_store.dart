import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StoredPhoto {
  const StoredPhoto(this.path, this.sizeBytes);
  final String path;
  final int sizeBytes;
}

/// Copies a picked photo into the app's private documents folder under a
/// random name, so the original file name and location are never stored.
class PhotoStore {
  const PhotoStore();

  Future<StoredPhoto> save(String sourcePath, {required String folder}) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(dir.path, folder));
    await target.create(recursive: true);
    final dest = p.join(target.path, '${const Uuid().v4()}${p.extension(sourcePath).toLowerCase()}');
    final copied = await File(sourcePath).copy(dest);
    return StoredPhoto(copied.path, await copied.length());
  }

  Future<void> deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
