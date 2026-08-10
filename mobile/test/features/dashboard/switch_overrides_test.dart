import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ws/state_dto.dart';
import 'package:unisync/features/dashboard/application/switch_overrides.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  SwitchState sw(String id, {required bool on}) => SwitchState(id: id, on: on);

  test('reconcile clears an override the snapshot confirms', () {
    final c = makeContainer();
    final n = c.read(switchOverridesProvider.notifier);
    n.set('ext0_1', false);
    expect(c.read(switchOverridesProvider), {'ext0_1': false});

    // Snapshot now reports it off — confirmed, so the override drops.
    n.reconcile([sw('ext0_1', on: false)]);
    expect(c.read(switchOverridesProvider), isEmpty);
  });

  test('reconcile keeps an override the snapshot still contradicts', () {
    final c = makeContainer();
    final n = c.read(switchOverridesProvider.notifier);
    n.set('ext0_1', false);

    // Stale/intermediate snapshot still shows it on — hold the override
    // so the tile doesn't flicker back on (the "All off" delay case).
    n.reconcile([sw('ext0_1', on: true)]);
    expect(c.read(switchOverridesProvider), {'ext0_1': false});

    // A later snapshot catches up — now it clears.
    n.reconcile([sw('ext0_1', on: false)]);
    expect(c.read(switchOverridesProvider), isEmpty);
  });

  test('reconcile drops an override for a switch missing from the snapshot', () {
    final c = makeContainer();
    final n = c.read(switchOverridesProvider.notifier);
    n.set('gone_1', true);

    n.reconcile([sw('ext0_1', on: false)]);
    expect(c.read(switchOverridesProvider), isEmpty);
  });

  test('safety timeout clears an override never confirmed', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      final n = c.read(switchOverridesProvider.notifier);
      n.set('ext0_1', false);
      expect(c.read(switchOverridesProvider), {'ext0_1': false});

      async.elapse(const Duration(seconds: 9));
      expect(c.read(switchOverridesProvider), isEmpty);
      c.dispose();
    });
  });
}
