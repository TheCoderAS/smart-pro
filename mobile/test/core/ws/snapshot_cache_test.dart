import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/ws/snapshot_cache.dart';
import 'package:unisync/core/ws/state_dto.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  const snap = StateSnapshot(
    masterName: 'Hallway',
    selfUid: 'AAAA1111',
    switches: [SwitchState(id: 'master_1', name: 'Hall', ch: 1, on: true)],
  );

  test('a saved snapshot comes back on the next launch', () async {
    // The whole point: someone reaching for their phone in the dark sees
    // the house immediately instead of a spinner.
    final first = ProviderContainer();
    await first.read(snapshotCacheProvider.notifier).save(snap);
    first.dispose();

    final next = ProviderContainer();
    addTearDown(next.dispose);
    // Restore is async, as it would be on a real cold start.
    next.read(snapshotCacheProvider);
    await Future<void>.delayed(Duration.zero);

    final restored = next.read(snapshotCacheProvider);
    expect(restored?.masterName, 'Hallway');
    expect(restored?.switches.single.on, isTrue);
  });

  test('a live snapshot replaces the cached one wholesale', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final cache = c.read(snapshotCacheProvider.notifier);

    await cache.save(snap);
    await cache.save(
      const StateSnapshot(masterName: 'Hallway', selfUid: 'AAAA1111'),
    );

    expect(c.read(snapshotCacheProvider)?.switches, isEmpty);
  });

  test('removing a master drops the cached house', () async {
    // Otherwise the next launch paints someone else's home.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(snapshotCacheProvider.notifier).save(snap);
    await c.read(snapshotCacheProvider.notifier).clear();

    expect(c.read(snapshotCacheProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SnapshotCacheNotifier.key), isNull);
  });

  test('unreadable cached data is ignored, not fatal', () async {
    SharedPreferences.setMockInitialValues({
      SnapshotCacheNotifier.key: 'not json',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(snapshotCacheProvider), isNull);
  });

  test('what is written is what the wire format produces', () async {
    // Guards against the DTO and the cache drifting apart — the cache
    // stores the same document the master sends.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(snapshotCacheProvider.notifier).save(snap);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(SnapshotCacheNotifier.key)!;
    expect(StateSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        snap);
  });
}
