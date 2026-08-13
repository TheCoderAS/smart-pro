import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/transport/ble_session.dart';

void main() {
  // The session used to give up the instant the link dropped: status went
  // to `failed` and nothing retried. Going out of range or power cycling
  // the master left the app reading "reconnecting" forever, and once the
  // engine started surviving a swipe from recents, reopening the app
  // stopped rescuing it too.
  group('reconnect backoff', () {
    test('starts quickly', () {
      expect(BleSessionController.retryDelay(0), const Duration(seconds: 1));
      expect(BleSessionController.retryDelay(1), const Duration(seconds: 2));
    });

    test('never decreases', () {
      var previous = Duration.zero;
      for (var i = 0; i < 20; i++) {
        final d = BleSessionController.retryDelay(i);
        expect(d, greaterThanOrEqualTo(previous));
        previous = d;
      }
    });

    // The cap is the whole point. Someone walking back into their own
    // hallway must not wait on an exponential that has grown to minutes,
    // so the schedule plateaus rather than doubling forever.
    test('caps so returning into range recovers on its own', () {
      for (var i = 0; i < 100; i++) {
        expect(
          BleSessionController.retryDelay(i),
          lessThanOrEqualTo(const Duration(seconds: 20)),
        );
      }
      expect(BleSessionController.retryDelay(99), const Duration(seconds: 20));
    });
  });
}
