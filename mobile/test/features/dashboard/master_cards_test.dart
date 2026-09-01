import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ws/state_dto.dart';
import 'package:unisync/features/dashboard/application/master_cards.dart';

void main() {
  const local = SwitchState(id: 'master_1', name: 'Hall', ch: 1);
  const localOffline =
      SwitchState(id: 'ext0_1', name: 'Gone', ch: 1, online: false);
  const peerSwitch = SwitchState(id: 'master_1', name: 'Kitchen', ch: 1);

  StateSnapshot snap({List<PeerState> peers = const []}) => StateSnapshot(
        masterName: 'Hallway',
        selfUid: 'AAAA1111',
        switches: const [local, localOffline],
        peers: peers,
      );

  group('sectionsFrom', () {
    test('a standalone master is one section, self first', () {
      final sections = sectionsFrom(snap(), const []);
      expect(sections, hasLength(1));
      expect(sections.single.isSelf, isTrue);
      expect(sections.single.name, 'Hallway');
    });

    test("an offline extension's switches leave the dashboard", () {
      // They stay in the extension list, marked offline — but they are not
      // rendered as tiles, greyed out or otherwise (story Epic 2).
      final sections = sectionsFrom(snap(), const []);
      expect(sections.single.switches.map((s) => s.id), ['master_1']);
    });

    test('every mesh peer gets its own section with its own switches', () {
      final sections = sectionsFrom(
        snap(peers: const [
          PeerState(uid: 'BBBB2222', name: 'Kitchen', switches: [peerSwitch]),
        ]),
        const [],
      );
      expect(sections, hasLength(2));
      expect(sections[1].isSelf, isFalse);
      expect(sections[1].uid, 'BBBB2222');
      expect(sections[1].switches.single.name, 'Kitchen');
    });

    test('card order is honoured, and unknown masters fall to the end', () {
      final sections = sectionsFrom(
        snap(peers: const [
          PeerState(uid: 'BBBB2222', name: 'Kitchen'),
          PeerState(uid: 'CCCC3333', name: 'Garage'),
        ]),
        // The user put the kitchen on top; the garage is new and unranked.
        const ['BBBB2222', 'AAAA1111'],
      );
      expect(
        sections.map((s) => s.uid),
        ['BBBB2222', 'AAAA1111', 'CCCC3333'],
      );
    });

    test('the connected master relays nothing — it drives its own relays', () {
      // Passing its own uid routes the command through the mesh relay
      // endpoint, which looks it up in the *peer* table, doesn't find it,
      // and 404s. Every switch silently stops working while touch, state
      // sync, rename and reorder all keep going — which is exactly how it
      // presented on the bench.
      final sections = sectionsFrom(
        snap(peers: const [PeerState(uid: 'BBBB2222', name: 'Kitchen')]),
        const [],
      );
      expect(sections[0].isSelf, isTrue);
      expect(sections[0].relayUid, isNull);
      // A peer does carry its uid, or the mesh couldn't be driven at all.
      expect(sections[1].relayUid, 'BBBB2222');
    });

    test('a standalone master also relays nothing', () {
      final sections = sectionsFrom(snap(), const []);
      expect(sections, hasLength(1));
      expect(sections.single.relayUid, isNull);
    });

    group('an offline master takes its switches with it', () {
      // The states a peer gossiped before it went are the last thing it
      // said, not the truth — they keep reporting themselves online. Left
      // in, they padded the count under the home's name and sat in the
      // card as tiles nothing would answer.
      List<MasterSection> withPeer(String presence) => sectionsFrom(
            snap(peers: [
              PeerState(
                uid: 'BBBB2222',
                name: 'Kitchen',
                presenceRaw: presence,
                switches: const [peerSwitch, localOffline],
              ),
            ]),
            const [],
          );

      test('offline: no switches, so nothing counts them', () {
        expect(withPeer('offline')[1].switches, isEmpty);
      });

      test('offline: and none are blamed on an extension', () {
        // The card says "Offline · last seen …". The dashboard's note
        // must not also claim an extension is unreachable.
        expect(withPeer('offline')[1].hiddenSwitches, 0);
      });

      test('online: its reachable switches are still there', () {
        final peer = withPeer('online')[1];
        expect(peer.switches.map((s) => s.id), ['master_1']);
        expect(peer.hiddenSwitches, 1); // the offline extension
      });

      test('intermittent keeps its switches', () {
        // Half of "intermittent" is a master that is up and settling.
        // Emptying a whole room every time one flaps is worse than the
        // flapping.
        expect(withPeer('intermittent')[1].switches, hasLength(1));
      });
    });

    test('an offline peer keeps its card', () {
      // Vanishing is the flapping the story rules out — the card stays,
      // showing the state, so nobody discovers it through a failed tap.
      final sections = sectionsFrom(
        snap(peers: const [
          PeerState(
            uid: 'BBBB2222',
            name: 'Kitchen',
            presenceRaw: 'offline',
            lastSeen: 120,
          ),
        ]),
        const [],
      );
      expect(sections, hasLength(2));
      expect(sections[1].online, isFalse);
      expect(sections[1].lastSeen, 120);
    });
  });
}
