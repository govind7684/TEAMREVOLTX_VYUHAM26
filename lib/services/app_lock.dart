import 'package:local_auth/local_auth.dart';

/// Fingerprint / face / device-PIN check used for the optional app lock and the
/// document vault. The system dialog does the work; the app never sees the
/// biometric data.
abstract class AppLock {
  /// True when this phone has a screen lock or biometrics set up.
  Future<bool> isAvailable();

  /// Shows the system prompt. False when cancelled, failed or unavailable.
  Future<bool> authenticate(String reason);
}

class DeviceAppLock implements AppLock {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}

/// For tests: answers without any system dialog.
class FakeAppLock implements AppLock {
  FakeAppLock({this.available = true, this.succeeds = true});
  final bool available, succeeds;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async => succeeds;
}
