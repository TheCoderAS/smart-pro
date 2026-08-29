import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/app/l10n/app_localizations.dart';
import 'package:unisync/features/auth/application/session.dart';
import 'package:unisync/features/auth/domain/models.dart';
import 'package:unisync/features/auth/presentation/login_screen.dart';

/// The post-removal wall: remove a switch, land on a login form for the
/// very switch that was removed (the phone is still on its Wi-Fi), and
/// have nowhere to go. With nothing paired the form is an adoption
/// offer, so it must carry an exit to the setup screen; with a home
/// paired it must not — wrong-network and unreachable own those cases.
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

  testWidgets('a paired home hides it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'masters': '[{"uid":"C5F77720","name":"Hall"}]',
    });
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('Set up a different'), findsNothing);
  });
}
