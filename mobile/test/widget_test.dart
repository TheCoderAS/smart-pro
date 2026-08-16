import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/core/wifi/wifi_service.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';
import 'package:unisync/main.dart';

/// Boot smoke test. The default (un-mocked) session hits an
/// unreachable master with nothing paired, so the app must land on the
/// setup screen rather than crashing, spinning forever — or showing the
/// dead-end "can't reach your switch".
class _UnreachableRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const Unreachable();
}

class _MockWifiService extends Mock implements WifiService {}

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));

  testWidgets('app boots to the setup screen without a device',
      (tester) async {
    // No paired master / no transport preference — the BLE cold-start
    // path stays dormant. Past the welcome screen: a fresh install lands
    // there instead, which has its own coverage in session_test.dart.
    SharedPreferences.setMockInitialValues({'firstrun.welcome': true});
    final wifi = _MockWifiService();
    when(() => wifi.masterReachable(timeout: any(named: 'timeout')))
        .thenAnswer((_) async => false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_UnreachableRepo()),
          wifiServiceProvider.overrideWithValue(wifi),
        ],
        child: const UnisyncApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up your switch'), findsOneWidget);
    expect(find.textContaining('check again'), findsOneWidget);
  });
}
