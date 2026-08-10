import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ws/state_dto.dart';
import 'package:unisync/features/mesh/domain/mesh_models.dart';

void main() {
  group('MeshPeer', () {
    test('reads presence and last-seen off the wire', () {
      final peer = MeshPeer.fromJson(const {
        'uid': 'C5F77720',
        'name': 'Hallway',
        'fw': '11.26.0',
        'online': false,
        'presence': 'intermittent',
        'last_seen': 95,
      });

      expect(peer.uid, 'C5F77720');
      expect(peer.presence, Presence.intermittent);
      expect(peer.lastSeen, 95);
    });

    test('only an online master can be removed', () {
      // Removal requires the target to delete its own mesh credentials and
      // say so. An offline master would keep them and rejoin when powered
      // on, so the app must not offer the action at all.
      MeshPeer at(String presence) =>
          MeshPeer(uid: 'AABBCCDD', presenceRaw: presence);

      expect(at('online').removable, isTrue);
      expect(at('offline').removable, isFalse);
      // Intermittent is a master that keeps dropping — a kick issued into
      // one of its gaps would report a removal that never happened.
      expect(at('intermittent').removable, isFalse);
    });

    test('a peer with no presence field is treated as online', () {
      // Older firmware sends neither field; the peer is in the list because
      // it was heard from, so the safe default is present.
      final peer = MeshPeer.fromJson(const {'uid': 'A1', 'name': 'Old'});
      expect(peer.presence, Presence.online);
      expect(peer.lastSeen, 0);
    });
  });

  group('lastSeenLabel', () {
    test('reads as elapsed time, not a clock', () {
      // The master has no clock, so last-seen is always relative.
      expect(lastSeenLabel(0), 'just now');
      expect(lastSeenLabel(30), '30s ago');
      expect(lastSeenLabel(95), '1 min ago');
      expect(lastSeenLabel(7200), '2 h ago');
      expect(lastSeenLabel(172800), '2 d ago');
    });
  });
}
