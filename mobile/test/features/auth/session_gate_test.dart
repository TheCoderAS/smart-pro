import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/app/l10n/app_localizations.dart';
import 'package:unisync/app/router.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/core/wifi/wifi_service.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';
import 'package:unisync/features/auth/presentation/session_gate.dart';

/// Bootstraps straight into the MasterUnreachable state — the screen a
/// locked-out user lands on, since they cannot join the master's Wi-Fi.
class _UnreachableRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw const Unreachable();
}

class _MockWifiService extends Mock implements WifiService {}

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));
  Widget wrap(ProviderContainer container, GoRouter router) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets(
      'unreachable screen offers BLE recovery and routes to it '
      '(lost-password escape hatch)', (tester) async {
    // A paired home whose master is not answering — the outage screen.
    // (With nothing paired, unreachable renders the setup screen instead;
    // that path has its own test below.)
    SharedPreferences.setMockInitialValues({
      'firstrun.welcome': true,
      'masters': '[{"uid":"C5F77720","name":"Hall"}]',
    });
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_UnreachableRepo()),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (context, state) => const SessionGate(),
        ),
        GoRoute(
          path: Routes.recovery,
          builder: (context, state) =>
              const Scaffold(body: Text('recovery-screen')),
        ),
      ],
    );

    await tester.pumpWidget(wrap(container, router));
    await tester.pumpAndSettle();

    // We're on the unreachable screen and the recovery affordance is here.
    expect(find.textContaining('reach your switch'), findsOneWidget);
    final recover = find.textContaining('Recover');
    expect(recover, findsOneWidget);

    // Tapping it navigates to the recovery flow — reachable while
    // logged out and off the master's Wi-Fi (the whole point).
    await tester.tap(recover);
    await tester.pumpAndSettle();
    expect(find.text('recovery-screen'), findsOneWidget);
  });

  testWidgets(
      'nothing paired and nobody answering renders the setup screen, '
      'not the dead-end unreachable screen', (tester) async {
    // The reinstall report: "set up my switch" landed on "can't reach
    // your switch" with no way to set anything up.
    SharedPreferences.setMockInitialValues({'firstrun.welcome': true});
    final wifi = _MockWifiService();
    when(() => wifi.masterReachable(timeout: any(named: 'timeout')))
        .thenAnswer((_) async => false);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_UnreachableRepo()),
        wifiServiceProvider.overrideWithValue(wifi),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (context, state) => const SessionGate(),
        ),
      ],
    );

    await tester.pumpWidget(wrap(container, router));
    await tester.pumpAndSettle();

    expect(find.text('Set up your switch'), findsOneWidget);
    expect(find.textContaining('check again'), findsOneWidget);
    expect(find.textContaining('reach your switch'), findsNothing);
  });
}
