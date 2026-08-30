import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/storage/master_registry.dart';

/// The home's mesh identity, and the rule that standalone never notices
/// any of it. The mesh id is what Bluetooth selects on, so a wrong value
/// here is the difference between roaming across the house and courting
/// a stranger.
void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  ProviderContainer withHome() {
    SharedPreferences.setMockInitialValues({
      'masters': jsonEncode([
        {'uid': 'C5F77720', 'name': 'Hall'},
      ]),
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  Future<SavedMaster> home(ProviderContainer c) async =>
      (await c.read(masterRegistryProvider.future)).single;

  test('a meshed master records its mesh id and name', () async {
    final c = withHome();
    await c.read(masterRegistryProvider.notifier).setMesh(
          uid: 'C5F77720',
          inMesh: true,
          meshId: 0x4F2A,
          meshName: 'UnisyncMesh',
        );

    final m = await home(c);
    expect(m.meshId, 0x4F2A);
    expect(m.meshName, 'UnisyncMesh');
    expect(m.inMesh, isTrue);
  });

  // The other direction matters just as much: a master that left a mesh
  // must stop vouching for its old mates, or Bluetooth keeps accepting
  // them for ever.
  test('leaving a mesh clears the id, so ex-mates stop being family',
      () async {
    final c = withHome();
    final reg = c.read(masterRegistryProvider.notifier);
    await reg.setMesh(
      uid: 'C5F77720',
      inMesh: true,
      meshId: 0x4F2A,
      meshName: 'UnisyncMesh',
    );
    await reg.setMesh(
      uid: 'C5F77720',
      inMesh: false,
      meshId: 0,
      meshName: '',
    );

    final m = await home(c);
    expect(m.meshId, isNull);
    expect(m.meshName, isNull);
    expect(m.inMesh, isFalse);
  });

  test('zero is never a valid mesh id', () async {
    final c = withHome();
    // Firmware that says "meshed" but has not derived an id yet must not
    // be able to write a zero — zero means standalone and matches
    // nothing.
    await c.read(masterRegistryProvider.notifier).setMesh(
          uid: 'C5F77720',
          inMesh: true,
          meshId: 0,
          meshName: 'UnisyncMesh',
        );

    final m = await home(c);
    expect(m.meshId, isNull);
    expect(m.inMesh, isFalse);
  });

  // The single-writer rule is not relaxed for mesh: only sign-in adds.
  test('mesh news about an unknown master adds nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(masterRegistryProvider.notifier).setMesh(
          uid: '2CEC97F0',
          inMesh: true,
          meshId: 0x4F2A,
          meshName: 'UnisyncMesh',
        );

    expect(await c.read(masterRegistryProvider.future), isEmpty);
  });

  test('mesh fields survive a name/ssid refresh', () async {
    final c = withHome();
    final reg = c.read(masterRegistryProvider.notifier);
    await reg.setMesh(
      uid: 'C5F77720',
      inMesh: true,
      meshId: 0x4F2A,
      meshName: 'UnisyncMesh',
    );
    await reg.ensure(uid: 'C5F77720', name: 'Living room', ssid: 'UnisyncMesh');

    final m = await home(c);
    expect(m.name, 'Living room');
    expect(m.meshId, 0x4F2A, reason: 'a rename must not drop the mesh id');
    expect(m.meshName, 'UnisyncMesh');
  });

  test('a standalone home stays standalone and unwritten', () async {
    final c = withHome();
    await c.read(masterRegistryProvider.notifier).setMesh(
          uid: 'C5F77720',
          inMesh: false,
          meshId: 0,
          meshName: '',
        );

    final m = await home(c);
    expect(m.meshId, isNull);
    expect(m.meshName, isNull);
    expect(m.name, 'Hall');
  });
}
