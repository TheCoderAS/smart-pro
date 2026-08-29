import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/storage/master_registry.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('ensure NEVER adds — only sign-in (setHome) does', () async {
    // The single-writer rule: a stale status update, in flight while the
    // user removed their switch, used to write the removed master right
    // back through ensure's old empty-list adoption. Adding is setHome's
    // job alone.
    final c = makeContainer();
    await c.read(masterRegistryProvider.future);

    await c.read(masterRegistryProvider.notifier).ensure(
          uid: 'C5F77720',
          name: 'Living Room',
        );
    expect(c.read(masterRegistryProvider).value, isEmpty,
        reason: 'a status update must never add a switch');

    await c.read(masterRegistryProvider.notifier).setHome(
          const SavedMaster(uid: 'C5F77720', name: 'Living Room'),
        );
    final masters = c.read(masterRegistryProvider).value!;
    expect(masters, hasLength(1));
    expect(masters.single.uid, 'C5F77720');
  });

  test('setHome replaces whatever the list held — ghosts included',
      () async {
    final c = makeContainer();
    await c.read(masterRegistryProvider.future);
    await c.read(masterRegistryProvider.notifier).setHome(
          const SavedMaster(uid: 'AAAA1111', name: 'Ghost'),
        );

    await c.read(masterRegistryProvider.notifier).setHome(
          const SavedMaster(uid: 'BBBB2222', name: 'Real'),
        );

    final masters = c.read(masterRegistryProvider).value!;
    expect(masters, hasLength(1));
    expect(masters.single.uid, 'BBBB2222',
        reason: 'the switch whose password just verified is the home');
  });

  test('ensure refreshes the name but keeps ssid and meshId', () async {
    final c = makeContainer();
    await c.read(masterRegistryProvider.future);
    await c.read(masterRegistryProvider.notifier).upsert(
          const SavedMaster(
            uid: 'C5F77720',
            name: 'Old',
            ssid: 'Unisync-1234',
            meshId: 4660,
          ),
        );

    await c
        .read(masterRegistryProvider.notifier)
        .ensure(uid: 'C5F77720', name: 'New Name');

    final m = c.read(masterRegistryProvider).value!.single;
    expect(m.name, 'New Name');
    expect(m.ssid, 'Unisync-1234'); // preserved
    expect(m.meshId, 4660); // preserved
  });

  test('ensure ignores an empty uid', () async {
    final c = makeContainer();
    await c.read(masterRegistryProvider.future);

    await c.read(masterRegistryProvider.notifier).ensure(uid: '');

    expect(c.read(masterRegistryProvider).value, isEmpty);
  });
}
