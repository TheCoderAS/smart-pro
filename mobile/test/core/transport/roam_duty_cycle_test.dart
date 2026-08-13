import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/transport/ble_session.dart';

/// The roam loop shares one radio with the live control link, and on
/// Android the link is what loses.
///
/// It woke every 3 seconds and scanned for 3, so a scan ended and the next
/// began — the radio was scanning essentially all the time while connected,
/// and control went from instant to horribly slow. The comment above the
/// loop had already blamed background scanning for exactly this once.
void main() {
  group('roam scanning stays out of the way', () {
    test('scans for a small fraction of each cycle', () {
      final duty = BleSessionController.roamWindow.inMilliseconds /
          BleSessionController.roamEvery.inMilliseconds;
      expect(duty, lessThanOrEqualTo(0.2),
          reason: 'a scan running most of the time starves the connection');
    });

    test('the window is shorter than the gap between scans', () {
      // Otherwise scans overlap and the radio never gets a quiet moment.
      expect(
        BleSessionController.roamWindow,
        lessThan(BleSessionController.roamEvery),
      );
    });

    test('holds off long enough after a command to cover a burst of taps',
        () {
      // Someone flipping several switches in a row must not have a scan
      // start between them.
      expect(
        BleSessionController.roamQuietFor,
        greaterThanOrEqualTo(const Duration(seconds: 5)),
      );
    });
  });
}
