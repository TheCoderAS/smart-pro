import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart'
    show ScanMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/ble/advert.dart';
import 'package:unisync/core/ble/ble_scanner.dart';
import 'package:unisync/core/logging/log_buffer.dart';
import 'package:unisync/core/transport/ble_session.dart';

class MockScanner extends Mock implements BleScanner {}

/// Mesh roaming: inside one home every master is interchangeable, so the
/// nearest one is the right one — walking from room to room must hand
/// over to whichever master is closest, not drag the phone back to the
/// uid it first signed in to.
///
/// Standalone keeps the opposite rule (the added uid wins outright,
/// however weak), which is what stops it courting a neighbour's master.
/// Both are asserted here so neither can be changed by accident.
void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(ScanMode.balanced);
  });

  const meshId = 0x4F2A;

  // The master the user signed in to — far away now, in another room.
  const signedInFar = MasterBeacon(
    deviceId: 'AA:AA:AA:AA:AA:AA',
    name: 'UC5F77720',
    rssi: -88,
    advert: MasterAdvert(
      meshId: meshId,
      inMesh: true,
      provisioned: true,
      clientConnected: false,
    ),
  );

  // A mate of the same mesh, in the room the phone is actually in.
  const mateNear = MasterBeacon(
    deviceId: 'BB:BB:BB:BB:BB:BB',
    name: 'U2CEC97F0',
    rssi: -42,
    advert: MasterAdvert(
      meshId: meshId,
      inMesh: true,
      provisioned: true,
      clientConnected: false,
    ),
  );

  ProviderContainer container(MockScanner scanner) {
    final c = ProviderContainer(overrides: [
      bleScannerProvider.overrideWithValue(scanner),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  MockScanner scannerHearing(List<MasterBeacon> beacons) {
    final scanner = MockScanner();
    when(() => scanner.collect(
          meshId: any(named: 'meshId'),
          window: any(named: 'window'),
          mode: any(named: 'mode'),
        )).thenAnswer((_) async => beacons);
    return scanner;
  }

  setUp(logBuffer.clear);

  test('a meshed home connects to the nearest mate, not the signed-in uid',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'masters': jsonEncode([
        {
          'uid': 'C5F77720',
          'name': 'Hall',
          'meshId': meshId,
          'meshName': 'UnisyncMesh',
        },
      ]),
    });
    final scanner = scannerHearing([signedInFar, mateNear]);
    final c = container(scanner);

    await c
        .read(bleSessionProvider.notifier)
        .activate(uid: 'C5F77720', meshId: meshId);

    // There is no BLE stack under a unit test, so the attempt fails
    // right after the choice and the failure state keeps no name. The
    // log is the durable record of which master was picked — and the
    // line a human reads when debugging this on real hardware.
    final chosen = logBuffer.lines
        .where((l) => l.contains('ble connecting'))
        .join('\n');
    expect(chosen, contains(mateNear.name),
        reason: 'the nearest mate of the same mesh should have been chosen');
    expect(chosen, isNot(contains(signedInFar.name)));
  });

  test('a standalone home still prefers its own master over a louder one',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'masters': jsonEncode([
        {'uid': 'C5F77720', 'name': 'Hall'},
      ]),
    });
    // Same two beacons, but this home has no mesh id: the far one is
    // ours, the loud one is a stranger.
    final scanner = scannerHearing([signedInFar, mateNear]);
    final c = container(scanner);

    await c.read(bleSessionProvider.notifier).activate(uid: 'C5F77720');

    final chosen = logBuffer.lines
        .where((l) => l.contains('ble connecting'))
        .join('\n');
    expect(chosen, isNot(contains(mateNear.name)),
        reason: 'standalone must never be lured away by a louder stranger');
  });
}
