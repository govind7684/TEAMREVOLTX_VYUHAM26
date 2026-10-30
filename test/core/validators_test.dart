import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/security/password_hasher.dart';
import 'package:civinex_ai/core/security/permissions.dart';
import 'package:civinex_ai/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators', () {
    test('report validation', () {
      expect(
          Validators.report(
              description: 'A proper description of the issue',
              locationText: 'Main Road',
              peopleAffected: 3),
          isEmpty);
      expect(
          Validators.report(description: 'x', locationText: '', peopleAffected: 0).length,
          3);
    });
    test('coordinates must be paired and inside Kerala', () {
      List<String> run(double? la, double? lo) => Validators.report(
          description: 'A proper description of the issue',
          locationText: 'Main Road',
          latitude: la,
          longitude: lo,
          peopleAffected: 1);
      expect(run(9.98, 76.3), isEmpty);
      expect(run(9.98, null), isNotEmpty);
      expect(run(28.6, 77.2), isNotEmpty); // Delhi
    });
    test('password, email, photo rules', () {
      expect(Validators.password('abc'), isNotNull);
      expect(Validators.password('allletters'), isNotNull);
      expect(Validators.password('Passw0rdX'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.photoFile('x.exe', 100), isNotNull);
      expect(Validators.photoFile('x.jpg', 6 * 1024 * 1024), isNotNull);
      expect(Validators.photoFile('x.JPG', 1000), isNull);
    });
  });

  group('PasswordHasher', () {
    test('verifies correct password only; salts differ', () {
      final salt = PasswordHasher.generateSalt();
      final h = PasswordHasher.hash('Secret123', salt);
      expect(PasswordHasher.verify('Secret123', salt, h), isTrue);
      expect(PasswordHasher.verify('secret123', salt, h), isFalse);
      expect(PasswordHasher.hash('Secret123', PasswordHasher.generateSalt()), isNot(h));
    });
  });

  group('Permissions.isValidTransition', () {
    test('terminal states are final; no self transitions', () {
      expect(Permissions.isValidTransition(IncidentStatus.resolved, IncidentStatus.inProgress),
          isFalse);
      expect(Permissions.isValidTransition(IncidentStatus.assigned, IncidentStatus.assigned),
          isFalse);
      expect(Permissions.isValidTransition(IncidentStatus.submitted, IncidentStatus.assigned),
          isTrue);
      expect(Permissions.isValidTransition(IncidentStatus.submitted, IncidentStatus.withdrawn),
          isFalse);
    });
  });
}
