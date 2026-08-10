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

  test('ensure adds a master not seen before', () async {
    final c = makeContainer();
    await c.read(masterRegistryProvider.future);

    await c.read(masterRegistryProvider.notifier).ensure(
          uid: 'C5F77720',
          name: 'Living Room',
        );

    final masters = c.read(masterRegistryProvider).value!;
    expect(masters, hasLength(1));
    expect(masters.single.uid, 'C5F77720');
    expect(masters.single.name, 'Living Room');
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
