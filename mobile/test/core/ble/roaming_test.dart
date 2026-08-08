
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ble/advert.dart';
import 'package:unisync/core/ble/roaming.dart';

MasterBeacon beacon(String id, int rssi, {int meshId = 0x1234, bool busy = false}) {
  return MasterBeacon(
    deviceId: id,
    name: 'U$id',
    rssi: rssi,
    advert: MasterAdvert(
      meshId: meshId,
      inMesh: true,
      provisioned: true,
      clientConnected: busy,
    ),
  );
}

/// Feeds a steady RSSI for a device across the dwell window.
void steady(RoamPolicy p, MasterBeacon b, {int from = 0, int to = 6000, int step = 1000}) {
  for (var t = from; t <= to; t += step) {
    p.observe(MasterBeacon(
      deviceId: b.deviceId,
      name: b.name,
      rssi: b.rssi,
      advert: b.advert,
    ), t);
  }
}

void main() {
  test('no hop when candidate is not 10 dB stronger', () {
    final p = RoamPolicy();
    steady(p, beacon('A', -60));
    steady(p, beacon('B', -55)); // only 5 dB stronger
    final hop = p.chooseHop(
      connectedDeviceId: 'A',
      candidates: [beacon('A', -60), beacon('B', -55)],
      nowMillis: 6000,
    );
    expect(hop, isNull);
  });

  test('hops when candidate is ≥10 dB stronger, sustained', () {
    final p = RoamPolicy();
    steady(p, beacon('A', -70));
    steady(p, beacon('B', -55)); // 15 dB stronger, whole window
    final hop = p.chooseHop(
      connectedDeviceId: 'A',
      candidates: [beacon('A', -70), beacon('B', -55)],
      nowMillis: 6000,
    );
    expect(hop, 'B');
  });

  test('a brief spike does not trigger a hop', () {
    final p = RoamPolicy();
    steady(p, beacon('A', -70));
    // B seen only once, just now — no sustained window.
    p.observe(beacon('B', -50), 6000);
    final hop = p.chooseHop(
      connectedDeviceId: 'A',
      candidates: [beacon('A', -70), beacon('B', -50)],
      nowMillis: 6000,
    );
    expect(hop, isNull);
  });

  test('does not hop before a full window of current data', () {
    final p = RoamPolicy();
    p.observe(beacon('A', -70), 6000); // single sample
    steady(p, beacon('B', -50));
    final hop = p.chooseHop(
      connectedDeviceId: 'A',
      candidates: [beacon('A', -70), beacon('B', -50)],
      nowMillis: 6000,
    );
    expect(hop, isNull);
  });

  test('ties break toward the unoccupied master', () {
    final p = RoamPolicy();
    steady(p, beacon('A', -70));
    steady(p, beacon('B', -55, busy: true));
    steady(p, beacon('C', -55));
    final hop = p.chooseHop(
      connectedDeviceId: 'A',
      candidates: [
        beacon('A', -70),
        beacon('B', -55, busy: true),
        beacon('C', -55),
      ],
      nowMillis: 6000,
    );
    expect(hop, 'C');
  });

  test('standalone masters never roam', () {
    final p = RoamPolicy();
    steady(p, beacon('A', -70, meshId: 0));
    steady(p, beacon('B', -50, meshId: 0));
    final hop = p.chooseHop(
      connectedDeviceId: 'A',
      candidates: [beacon('A', -70, meshId: 0), beacon('B', -50, meshId: 0)],
      nowMillis: 6000,
    );
    expect(hop, isNull);
  });

  test('a synthetic walk does not oscillate', () {
    final p = RoamPolicy();
    var connected = 'A';
    var hops = 0;
    // Walk from A to B: A fades -55→-80, B rises -80→-55 over 20 s.
    for (var t = 0; t <= 20000; t += 1000) {
      final frac = t / 20000;
      final aR = (-55 - 25 * frac).round();
      final bR = (-80 + 25 * frac).round();
      final beams = [beacon('A', aR), beacon('B', bR)];
      for (final b in beams) {
        p.observe(b, t);
      }
      final hop = p.chooseHop(
        connectedDeviceId: connected,
        candidates: beams,
        nowMillis: t,
      );
      if (hop != null && hop != connected) {
        connected = hop;
        hops++;
      }
    }
    // Should end on B and have hopped exactly once (no flapping).
    expect(connected, 'B');
    expect(hops, 1);
  });
}
