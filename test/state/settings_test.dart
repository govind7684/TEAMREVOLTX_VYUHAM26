import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/services/prefs.dart';
import 'package:civinex_ai/state/providers.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme defaults to dark and the choice is remembered', () {
    final prefs = Prefs.memory();
    final a = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    expect(a.read(themeModeProvider), ThemeMode.dark);
    a.read(themeModeProvider.notifier).set(ThemeMode.light);
    final b = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    expect(b.read(themeModeProvider), ThemeMode.light);
  });

  test('app lock starts locked only when enabled and someone was restored', () {
    const user = AppUser(id: 'u', name: 'A B', email: 'a@b.co', role: UserRole.citizen);
    ProviderContainer make({required bool on, AppUser? restored}) {
      final prefs = Prefs.memory()..setBool('app_lock', on);
      return ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        initialUserProvider.overrideWithValue(restored),
      ]);
    }

    expect(make(on: true, restored: user).read(appLockedProvider), isTrue);
    expect(make(on: false, restored: user).read(appLockedProvider), isFalse);
    expect(make(on: true).read(appLockedProvider), isFalse);
  });

  test('prefs store and clear values', () async {
    final p = Prefs.memory();
    await p.setBool('x', true);
    expect(p.getBool('x'), isTrue);
    await p.setBool('x', false);
    expect(p.getBool('x'), isFalse);
    await p.set('k', 'v');
    expect(p.get('k'), 'v');
  });
}
