import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/transport/link_state.dart';

void main() {
  group('LinkState', () {
    test('only a confirmed link enables controls', () {
      // The whole point of the story rule: a user must never be able to tap
      // a switch and find out that way that the app lost the master.
      expect(LinkState.connectedWifi.controlsEnabled, isTrue);
      expect(LinkState.connectedBle.controlsEnabled, isTrue);
      expect(LinkState.reconnecting.controlsEnabled, isFalse);
      expect(LinkState.outOfRange.controlsEnabled, isFalse);
    });

    test('grace window is shorter than the out-of-range threshold', () {
      // A roaming handoff must resolve inside the grace window without the
      // user seeing anything; a real loss must escalate past it. If these
      // ever cross, roaming flaps or a dead link stays silent forever.
      expect(LinkMonitor.grace, lessThan(LinkMonitor.outOfRangeAfter));
      // ~5 s to reflect a genuine loss: one missed heartbeat plus grace.
      expect(
        LinkMonitor.heartbeatEvery + LinkMonitor.grace,
        lessThanOrEqualTo(const Duration(seconds: 8)),
      );
    });
  });
}
