import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/features/lock/app_lock_gate.dart';
import 'package:civinex_ai/services/app_lock.dart';
import 'package:civinex_ai/services/prefs.dart';
import 'package:civinex_ai/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = AppUser(id: 'u1', name: 'Asha', email: 'asha@example.com', role: UserRole.citizen);

Widget _app({required bool lockOn, required AppLock lock, AppUser? restored = _user}) {
  final prefs = Prefs.memory()..setBool('app_lock', lockOn);
  return ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      appLockProvider.overrideWithValue(lock),
      initialUserProvider.overrideWithValue(restored),
    ],
    child: const MaterialApp(home: AppLockGate(child: Text('INSIDE'))),
  );
}

void main() {
  testWidgets('lock off: the app opens straight away', (tester) async {
    await tester.pumpWidget(_app(lockOn: false, lock: FakeAppLock()));
    expect(find.text('INSIDE'), findsOneWidget);
  });

  testWidgets('lock on with a remembered user: asks to unlock, then opens', (tester) async {
    await tester.pumpWidget(_app(lockOn: true, lock: FakeAppLock(succeeds: true)));
    await tester.pumpAndSettle();
    expect(find.text('INSIDE'), findsOneWidget); // the automatic prompt succeeded
  });

  testWidgets('lock on and the check fails: stays locked and offers retry', (tester) async {
    await tester.pumpWidget(_app(lockOn: true, lock: FakeAppLock(succeeds: false)));
    await tester.pumpAndSettle();
    expect(find.text('INSIDE'), findsNothing);
    expect(find.text('CIVINEX AI is locked'), findsOneWidget);
    expect(find.text('Could not verify it is you.'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
