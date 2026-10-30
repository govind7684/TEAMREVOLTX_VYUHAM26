import 'package:civinex_ai/core/constants/brand.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import 'package:civinex_ai/features/about/about_screen.dart';
import 'package:civinex_ai/features/auth/auth_flow.dart';
import 'package:civinex_ai/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/demo_seeder.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  /// An empty database with departments only: what a brand-new install has.
  Future<Widget> app(WidgetTester tester, Widget home, {bool onboarded = true}) async {
    final db = await tester.runAsync(() async {
      final d = await AppDatabase.open(path: inMemoryDatabasePath);
      await DemoSeeder.ensureDepartments(d);
      return d;
    });
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db!),
        onboardedProvider.overrideWith((ref) => onboarded),
      ],
      child: MaterialApp(home: home),
    );
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('welcome offers Citizen Login and Administrator Login, with no demo wording',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(await app(tester, const AuthFlow()));
    expect(find.text('Citizen Login'), findsOneWidget);
    expect(find.text('Administrator Login'), findsOneWidget);
    expect(find.textContaining('DEMO'), findsNothing);
    expect(find.textContaining('Demo'), findsNothing);
  });

  testWidgets('first run shows onboarding once, Skip leads to the welcome page', (tester) async {
    phone(tester);
    await tester.pumpWidget(await app(tester, const AuthFlow(), onboarded: false));
    expect(find.text('Report in seconds'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Citizen Login'), findsOneWidget);
  });

  testWidgets('citizen login validates empty fields and can switch to registration',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(await app(tester, const AuthFlow()));
    await tester.tap(find.text('Citizen Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.tap(find.text('New here? Register'));
    await tester.pumpAndSettle();
    expect(find.text('Create citizen account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);
  });

  testWidgets('administrator login has no self-registration', (tester) async {
    phone(tester);
    await tester.pumpWidget(await app(tester, const AuthFlow()));
    await tester.tap(find.text('Administrator Login'));
    await tester.pumpAndSettle();
    expect(find.text('New here? Register'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Full name'), findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('citizen registration checks that the passwords match', (tester) async {
    phone(tester);
    await tester.pumpWidget(await app(tester, const AuthFlow()));
    await tester.tap(find.text('Citizen Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New here? Register'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'Passw0rdX');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'different1');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('forgot password explains how a reset works on this build', (tester) async {
    phone(tester);
    await tester.pumpWidget(await app(tester, const AuthFlow()));
    await tester.tap(find.text('Citizen Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('administrator'), findsWidgets);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot your password?'), findsNothing);
  });

  testWidgets('the auth pages carry the event identity', (tester) async {
    phone(tester);
    await tester.pumpWidget(await app(tester, const AuthFlow()));
    expect(find.text(Brand.eventLine), findsWidgets);
    expect(find.text(Brand.appName), findsWidgets);
  });

  testWidgets('About screen names the event and says it is not an official product',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, const AboutScreen()));
    expect(find.text(Brand.eventLine), findsOneWidget);
    expect(find.textContaining('not an official product'), findsOneWidget);
  });

  test('brand line contains all three event names', () {
    expect(Brand.eventLine, contains('Vyuham 26'));
    expect(Brand.eventLine, contains('Agent Forge Hackathon'));
    expect(Brand.eventLine, contains('Digital University Kerala'));
  });
}
