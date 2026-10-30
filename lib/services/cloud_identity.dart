import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/errors/app_exceptions.dart';

/// The few cloud operations the app needs: Firebase Authentication for who a
/// person is, and one Firestore document per person (`users/{uid}`) for their
/// name, role, department and active flag.
///
/// Everything else in the app still uses the phone's own database. This
/// interface exists so the account logic can be tested without Firebase.
abstract class CloudIdentity {
  /// The signed-in Firebase user's id, or null. Firebase keeps this across
  /// restarts until sign-out.
  String? get currentUid;

  /// Signs in. Returns the user id.
  Future<String> signIn(String email, String password);

  /// Creates an account and signs in as it. Returns the user id.
  Future<String> createAccount(String email, String password);

  /// Creates an account WITHOUT changing who is signed in (an administrator
  /// adding an officer). Returns the new user id.
  Future<String> createAccountForSomeoneElse(String email, String password);

  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> sendVerificationEmail();

  /// Re-reads the account and says whether its email has been verified.
  Future<bool> isEmailVerified();

  /// True when [password] is the signed-in user's current password.
  Future<bool> verifyPassword(String password);
  Future<void> updatePassword(String newPassword);

  Future<Map<String, Object?>?> getProfile(String uid);
  Future<void> setProfile(String uid, Map<String, Object?> data, {bool merge = false});
  Future<List<Map<String, Object?>>> listProfiles();
}

class FirebaseIdentity implements CloudIdentity {
  FirebaseIdentity()
      : _auth = FirebaseAuth.instance,
        _fs = FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _fs;

  /// Starts Firebase using android/app/google-services.json. Returns null when
  /// that file is missing or invalid, and the app then runs in local mode.
  static Future<FirebaseIdentity?> tryStart() async {
    try {
      await Firebase.initializeApp();
      return FirebaseIdentity();
    } catch (_) {
      return null;
    }
  }

  @override
  String? get currentUid => _auth.currentUser?.uid;

  Future<T> _wrap<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const PermissionDeniedException('The server refused this action.');
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw const ValidationException(['No internet connection. Try again when you are online.']);
      }
      throw ValidationException(['Cloud error (${e.code}).']);
    } on TimeoutException {
      throw const ValidationException(['The server did not answer. Check your internet connection.']);
    }
  }

  static AppException _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return const ValidationException(['An account with this email already exists.']);
      case 'invalid-email':
        return const ValidationException(['Enter a valid email address.']);
      case 'weak-password':
        return const ValidationException(['Choose a stronger password.']);
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return const ValidationException(['Incorrect email or password.']);
      case 'user-disabled':
        return const PermissionDeniedException('This account is disabled.');
      case 'too-many-requests':
        return const ValidationException(['Too many attempts. Wait a few minutes and try again.']);
      case 'network-request-failed':
        return const ValidationException(['No internet connection. Signing in needs internet.']);
      case 'requires-recent-login':
        return const ValidationException(['Please sign out and sign in again, then retry.']);
      default:
        return ValidationException(['Sign-in failed (${e.code}).']);
    }
  }

  @override
  Future<String> signIn(String email, String password) => _wrap(() async {
        final c = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
        return c.user!.uid;
      });

  @override
  Future<String> createAccount(String email, String password) => _wrap(() async {
        final c = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
        return c.user!.uid;
      });

  @override
  Future<String> createAccountForSomeoneElse(String email, String password) => _wrap(() async {
        // A second Firebase app instance, so the administrator stays signed in.
        FirebaseApp app;
        try {
          app = Firebase.app('staff-creator');
        } catch (_) {
          app = await Firebase.initializeApp(name: 'staff-creator', options: Firebase.app().options);
        }
        final other = FirebaseAuth.instanceFor(app: app);
        try {
          final c = await other.createUserWithEmailAndPassword(email: email.trim(), password: password);
          return c.user!.uid;
        } finally {
          await other.signOut();
        }
      });

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _wrap(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> sendVerificationEmail() => _wrap(() async {
        final u = _auth.currentUser;
        if (u != null && !u.emailVerified) await u.sendEmailVerification();
      });

  @override
  Future<bool> isEmailVerified() async {
    try {
      final u = _auth.currentUser;
      if (u == null) return false;
      await u.reload();
      return _auth.currentUser?.emailVerified ?? false;
    } catch (_) {
      return _auth.currentUser?.emailVerified ?? false;
    }
  }

  @override
  Future<bool> verifyPassword(String password) async {
    final u = _auth.currentUser;
    if (u == null || u.email == null) return false;
    try {
      await u.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: u.email!, password: password));
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') throw _authError(e);
      return false;
    }
  }

  @override
  Future<void> updatePassword(String newPassword) => _wrap(() async {
        final u = _auth.currentUser;
        if (u == null) throw const PermissionDeniedException('You are not signed in.');
        await u.updatePassword(newPassword);
      });

  @override
  Future<Map<String, Object?>?> getProfile(String uid) => _wrap(() async {
        final s = await _fs.collection('users').doc(uid).get().timeout(const Duration(seconds: 10));
        if (!s.exists) return null;
        return {...s.data()!, 'id': s.id};
      });

  @override
  Future<void> setProfile(String uid, Map<String, Object?> data, {bool merge = false}) =>
      _wrap(() => _fs.collection('users').doc(uid).set(data, SetOptions(merge: merge)));

  @override
  Future<List<Map<String, Object?>>> listProfiles() => _wrap(() async {
        final s = await _fs.collection('users').get().timeout(const Duration(seconds: 10));
        return [for (final d in s.docs) {...d.data(), 'id': d.id}];
      });
}
