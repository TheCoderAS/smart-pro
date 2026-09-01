import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ble/ble_control_client.dart';
import 'package:unisync/core/ble/ble_scanner.dart';
import 'package:unisync/core/transport/ble_session.dart';

/// A timeout shorter than the work it wraps is not a safety net, it is a
/// guaranteed failure — and this one was exact.
///
/// The session capped a scan at `window + 10s`: 16 s for its 6 s window.
/// The scanner could legitimately spend `8s (waiting out a hung cancel)
/// + 6s (the window) + 2s (its own cancel)` — the same 16 s. So the cap
/// expired at the instant collect() returned, its beacons were thrown
/// away unread, and the failure surfaced as "ble connect failed" from a
/// run that had never attempted a connection. An hour of a bench session
/// went into that one line.
///
/// These are pure arithmetic on the published constants. They cost
/// nothing and they would have caught it outright.
void main() {
  /// The longest a collect can honestly take, spelled out here rather
  /// than borrowed from [BleScanner.budget] — a budget checked against
  /// itself proves nothing.
  Duration worstCase(Duration window) =>
      window +
      BleScanner.hungCancelGrace +
      BleScanner.resetCap +
      BleScanner.cancelGrace;

  const windows = [Duration(seconds: 4), Duration(seconds: 6)];

  group('the scanner\'s published budget', () {
    test('covers every step collect can take', () {
      for (final w in windows) {
        expect(BleScanner.budget(w), worstCase(w), reason: 'window $w');
      }
    });

    test('grows with the window it is given', () {
      expect(
        BleScanner.budget(const Duration(seconds: 6)),
        greaterThan(BleScanner.budget(const Duration(seconds: 4))),
      );
    });
  });

  group('the session\'s caps', () {
    test('give a scan strictly more time than it can spend', () {
      for (final w in windows) {
        final cap = BleScanner.budget(w) + BleSessionController.scanOpGrace;
        // greaterThan, never greaterThanOrEqualTo: equal is the bug.
        expect(cap, greaterThan(worstCase(w)), reason: 'window $w');
      }
    });

    test('outlast a full scan followed by a full connect', () {
      const window = Duration(seconds: 6);
      final scanCap = BleScanner.budget(window) + BleSessionController.scanOpGrace;
      expect(
        BleSessionController.linkOpCap,
        greaterThan(scanCap + BleControlClient.connectTimeout),
      );
    });
  });

  test('a wedged scanner is given up on long before the backoff caps', () {
    // Three empty scans must be reachable well inside a stretch of
    // retries, or the reset that unwedges the radio never runs.
    final toReset = BleSessionController.retryDelay(0) *
        BleScanner.emptyScansBeforeReset;
    expect(toReset, lessThan(BleScanner.resetCooldown));
  });
}
