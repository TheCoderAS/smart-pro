import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart'
    show ScanMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/core/ble/ble_scanner.dart';
import 'package:unisync/core/storage/master_registry.dart';
import 'package:unisync/core/storage/secure_store.dart';
import 'package:unisync/core/transport/control_transport.dart';
import 'package:unisync/core/transport/transport_coordinator.dart';
import 'package:unisync/core/transport/transport_manager.dart';
import 'package:unisync/features/auth/application/session.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';

class MockSecureStore extends Mock implements SecureStore {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockScanner extends Mock implements BleScanner {}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(ScanMode.balanced);
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'firstrun.welcome': true});
  });

  String masters(List<Map<String, Object?>> ms) => jsonEncode(ms);

  group('per-master preference', () {
    test('preferredTransport parses, and junk degrades to null', () {
      const a = SavedMaster(uid: 'A', name: 'A', preferredMode: 'bluetooth');
      const b = SavedMaster(uid: 'B', name: 'B', preferredMode: 'hovercraft');
      const c = SavedMaster(uid: 'C', name: 'C');
      expect(a.preferredTransport, TransportPreference.bluetooth);
      expect(b.preferredTransport, isNull);
      expect(c.preferredTransport, isNull);
    });

    test('setPreferredMode persists and survives a reload', () async {
      SharedPreferences.setMockInitialValues({
        'masters': masters([
          {'uid': 'AAA', 'name': 'Hall'},
        ]),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(masterRegistryProvider.future);
      await c
          .read(masterRegistryProvider.notifier)
          .setPreferredMode('AAA', 'bluetooth');

      final again = ProviderContainer();
      addTearDown(again.dispose);
      final loaded = await again.read(masterRegistryProvider.future);
      expect(loaded.single.preferredTransport, TransportPreference.bluetooth);
    });

    // The bug this exists for: the active master's own choice must win,
    // and a master with no choice falls back to the global setting —
    // setting Bluetooth for the shed must not flip the hall.
    test('effectivePreference: own choice beats global, absence falls back',
        () async {
      SharedPreferences.setMockInitialValues({
        'firstrun.welcome': true,
        TransportPreferenceNotifier.key: 'wifi',
        'masters': masters([
          {'uid': 'AAA', 'name': 'Hall'},
          {'uid': 'BBB', 'name': 'Shed', 'preferredMode': 'bluetooth'},
        ]),
        'masters.lastUsed': 'BBB',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(
        await c.read(transportCoordinatorProvider).effectivePreference(),
        TransportPreference.bluetooth,
      );

      // Move to the hall, which has no choice of its own → global wins.
      await c.read(masterRegistryProvider.future);
      await c.read(masterRegistryProvider.notifier).setLastUsed('AAA');
      expect(
        await c.read(transportCoordinatorProvider).effectivePreference(),
        TransportPreference.wifi,
      );
    });
  });

  group('switching masters', () {
    // A failed switch must leave the session it interrupted untouched.
    // The old flow went to loading first and parked on a disconnected
    // screen even though the master it came from was still working.
    test('a BLE target that is not visible keeps the current session',
        () async {
      SharedPreferences.setMockInitialValues({
        'firstrun.welcome': true,
        'masters': masters([
          {'uid': 'AAA', 'name': 'Hall'},
          {'uid': 'BBB', 'name': 'Shed', 'preferredMode': 'bluetooth'},
        ]),
        'masters.lastUsed': 'AAA',
      });
      final repo = MockAuthRepository();
      final store = MockSecureStore();
      final scanner = MockScanner();
      // The current master is unreachable over Wi-Fi so the bootstrap
      // settles on a known state we can assert is preserved.
      when(() => repo.info()).thenThrow(const Unreachable());
      when(() => store.readToken(any())).thenAnswer((_) async => 'tok');
      when(() => scanner.collect(
            meshId: any(named: 'meshId'),
            window: any(named: 'window'),
            mode: any(named: 'mode'),
          )).thenAnswer((_) async => const []); // nothing in sight

      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        secureStoreProvider.overrideWithValue(store),
        bleScannerProvider.overrideWithValue(scanner),
      ]);
      addTearDown(c.dispose);

      final before = await c.read(sessionProvider.future);

      final result = await c.read(sessionProvider.notifier).switchTo(
            const SavedMaster(
                uid: 'BBB', name: 'Shed', preferredMode: 'bluetooth'),
          );

      expect(result, SwitchAttempt.unreachable);
      // Same state object — not a loading flash, not a new dead end.
      expect(c.read(sessionProvider).value, same(before));
      // And the app still opens on the master it was on.
      expect(
        await c.read(masterRegistryProvider.notifier).lastUsed(),
        'AAA',
      );
    });

    test('a BLE target with no token asks for a Wi-Fi sign-in', () async {
      SharedPreferences.setMockInitialValues({
        'firstrun.welcome': true,
        'masters': masters([
          {'uid': 'AAA', 'name': 'Hall'},
          {'uid': 'BBB', 'name': 'Shed', 'preferredMode': 'bluetooth'},
        ]),
        'masters.lastUsed': 'AAA',
      });
      final repo = MockAuthRepository();
      final store = MockSecureStore();
      when(() => repo.info()).thenThrow(const Unreachable());
      when(() => store.readToken(any())).thenAnswer((_) async => null);

      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        secureStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      await c.read(sessionProvider.future);

      final result = await c.read(sessionProvider.notifier).switchTo(
            const SavedMaster(
                uid: 'BBB', name: 'Shed', preferredMode: 'bluetooth'),
          );

      expect(result, SwitchAttempt.needsWifiLogin);
    });
  });
}
