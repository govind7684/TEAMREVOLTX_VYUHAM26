import 'dart:async';

// geolocator has its own PermissionDeniedException; we use the app's.
import 'package:geolocator/geolocator.dart' hide PermissionDeniedException;
import 'package:latlong2/latlong.dart';

import '../core/errors/app_exceptions.dart';

/// GPS access, only ever started by an explicit tap, and only after the
/// person grants permission. Nothing is stored or sent anywhere.
///
/// Tries a precise fix first, then a coarser one, then the phone's last known
/// position, so it still works indoors or with a weak GPS signal.
class LocationService {
  const LocationService();

  Future<LatLng> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const PermissionDeniedException(
            'Location (GPS) is switched off on this phone. Turn it on in the quick '
            'settings, then tap again. Or pick the spot on the map.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const PermissionDeniedException(
            'Location permission was not granted. Tap again and choose "While using the app", '
            'or pick the spot on the map.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw const PermissionDeniedException(
            'Location permission is blocked. Open Settings, Apps, CIVINEX AI, Permissions, '
            'Location and allow it, or pick the spot on the map.');
      }

      Position? pos;
      for (final attempt in const [
        (LocationAccuracy.high, 12),
        (LocationAccuracy.low, 10),
      ]) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: attempt.$1,
              timeLimit: Duration(seconds: attempt.$2),
            ),
          );
          break;
        } on TimeoutException {
          // Try the next, coarser attempt.
        }
      }
      pos ??= await Geolocator.getLastKnownPosition();
      if (pos == null) {
        throw const PermissionDeniedException(
            'Could not get a GPS fix. Go near a window or outside, check that Location is on '
            'and set to high accuracy, then try again. Or pick the spot on the map.');
      }
      return LatLng(pos.latitude, pos.longitude);
    } on AppException {
      rethrow;
    } catch (e) {
      // The app was built without the location permission lines in
      // AndroidManifest.xml. Reinstalling after adding them fixes it.
      final kind = e.runtimeType.toString();
      if (kind.contains('PermissionDefinitionsNotFound')) {
        throw const PermissionDeniedException(
            'This build is missing the location permission. Run tools\\fix_android.ps1 '
            '(or add the permission lines to AndroidManifest.xml), then reinstall the app.');
      }
      throw PermissionDeniedException(
          'Could not get your location ($kind). Pick the spot on the map instead.');
    }
  }
}
