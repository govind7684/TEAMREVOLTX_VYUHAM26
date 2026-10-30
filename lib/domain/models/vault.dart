/// Kinds of personal document a citizen can keep in the vault.
enum VaultCategory {
  aadhaar('Aadhaar Card', false),
  voterId('Voter ID', false),
  drivingLicence('Driving Licence', true),
  pan('PAN Card', false),
  passport('Passport', true),
  studentId('Student ID Card', true),
  rationCard('Ration Card', false),
  property('Property Documents', false),
  bill('Electricity & Water Bills', false),
  other('Other', true);

  const VaultCategory(this.label, this.usuallyExpires);
  final String label;

  /// Whether the upload form should suggest setting an expiry date.
  final bool usuallyExpires;
}

class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.category,
    required this.title,
    required this.originalName,
    required this.mime,
    required this.sizeBytes,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id, title, originalName, mime;
  final VaultCategory category;
  final int sizeBytes;
  final DateTime? expiresAt;
  final DateTime createdAt, updatedAt;

  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  /// Whole days until expiry (negative once expired); null without an expiry.
  int? daysToExpiry(DateTime now) {
    final e = expiresAt;
    if (e == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(e.year, e.month, e.day).difference(today).inDays;
  }

  String get sizeText {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory VaultDocument.fromMap(Map<String, Object?> m) => VaultDocument(
        id: m['id'] as String,
        category: VaultCategory.values.byName(m['category'] as String),
        title: m['title'] as String,
        originalName: m['original_name'] as String,
        mime: m['mime'] as String,
        sizeBytes: m['size_bytes'] as int,
        expiresAt: m['expires_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['expires_at'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}

/// A document together with its decrypted bytes. Keep it in memory only as
/// long as needed.
class VaultFile {
  const VaultFile(this.document, this.bytes);
  final VaultDocument document;
  final List<int> bytes;
}
