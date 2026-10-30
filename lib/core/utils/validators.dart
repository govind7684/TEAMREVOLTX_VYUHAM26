class Validators {
  // Loose bounding box around Kerala (with margin) to catch typos.
  static const latMin = 8.0, latMax = 13.0, lonMin = 74.5, lonMax = 77.7;

  static const maxPhotoBytes = 5 * 1024 * 1024;
  static const allowedPhotoExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  static String? name(String? v) {
    final s = v?.trim() ?? '';
    if (s.length < 2) return 'Enter your name (at least 2 characters).';
    if (s.length > 80) return 'Name is too long.';
    return null;
  }

  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  static bool inKerala(double lat, double lng) =>
      lat >= latMin && lat <= latMax && lng >= lonMin && lng <= lonMax;

  /// Returns a list of human-readable problems (empty when valid).
  static List<String> report({
    required String description,
    required String locationText,
    double? latitude,
    double? longitude,
    required int peopleAffected,
  }) {
    final errors = <String>[];
    final d = description.trim();
    if (d.length < 10) errors.add('Describe the problem in at least 10 characters.');
    if (d.length > 1000) errors.add('Description must be under 1000 characters.');
    if (locationText.trim().length < 3) {
      errors.add('Enter a location (street, landmark or area).');
    }
    if ((latitude == null) != (longitude == null)) {
      errors.add('Enter both latitude and longitude, or leave both empty.');
    } else if (latitude != null && longitude != null) {
      if (!inKerala(latitude, longitude)) {
        errors.add('Coordinates look outside Kerala. Check latitude and longitude.');
      }
    }
    if (peopleAffected < 1 || peopleAffected > 100000) {
      errors.add('People affected must be a positive number.');
    }
    return errors;
  }

  static String? photoFile(String path, int sizeBytes) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    if (!allowedPhotoExtensions.contains(ext)) {
      return 'Only JPG, PNG or WebP photos are allowed.';
    }
    if (sizeBytes > maxPhotoBytes) return 'Photo must be 5 MB or smaller.';
    if (sizeBytes == 0) return 'That photo file is empty.';
    return null;
  }
}
