import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/app/l10n/app_localizations.dart';
import 'package:unisync/features/auth/application/session.dart';
import 'package:unisync/features/auth/domain/models.dart';
import 'package:unisync/features/auth/presentation/login_screen.dart';

/// By decree, no screen is a dead end: the sign-in form always carries
/// the "set up a different switch" escape, whatever the registry holds.
void main() {
  const info = DeviceInfo(
    uptime: 1,
    freeHeap: 1000,
    uid: 'C5F77720',
    fw: '11.29.3',
    auth: true,
  );

  Widget wrap() => const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginScreen(state: NeedsLogin(info)),
        ),
      );

  testWidgets('nothing paired → the form offers the setup escape',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('Set up a different'), findsOneWidget);
  });

  testWidgets('a paired home still has the escape (no dead ends, ever)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'masters': '[{"uid":"C5F77720","name":"Hall"}]',
    });
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('Set up a different'), findsOneWidget);
  });
}
