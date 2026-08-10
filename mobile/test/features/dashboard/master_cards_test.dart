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
