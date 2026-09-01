import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unisync/core/transport/control_transport.dart';
import 'package:unisync/core/transport/transport_manager.dart';
import 'package:unisync/features/mesh/data/mesh_repository.dart';
import 'package:unisync/features/mesh/domain/mesh_models.dart';

class MockTransport extends Mock implements ControlTransport {}

/// The Mesh screen renders nothing until mesh status resolves, and it
/// reads that status through the active transport.
///
/// It used to read it straight off MeshRepository — plain HTTP. So while
/// leaving a mesh and removing a master had both been given BLE verbs and
/// transport methods, in Bluetooth mode the screen carrying those buttons
/// could not load at all: it fell to its error arm and the buttons never
/// rendered. The doors were fitted and the room was sealed.
void main() {
  late MockTransport transport;

  const status = MeshStatus(
    active: true,
    meshName: 'UnisyncMesh',
    peerCount: 1,
    peers: [MeshPeer(uid: '2CEC97F0', name: "Aalok's Room")],
  );

  setUp(() {
    transport = MockTransport();
    when(() => transport.meshStatus()).thenAnswer((_) async => status);
  });

  ProviderContainer make() {
    final c = ProviderContainer(
      overrides: [activeControlProvider.overrideWithValue(transport)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('status comes from the active transport, whichever it is', () async {
    final c = make();
    expect(await c.read(meshStatusProvider.future), status);
    verify(() => transport.meshStatus()).called(1);
  });

  test('the member list survives the trip — it is what the screen draws',
      () async {
    // A count without a list is what the BLE `mesh` verb used to answer,
    // and _PeerTile has nothing to render from that.
    final c = make();
    final s = await c.read(meshStatusProvider.future);
    expect(s.peers, hasLength(1));
    expect(s.peers.single.uid, '2CEC97F0');
    expect(s.peers.single.name, "Aalok's Room");
  });

  test('a refresh asks the transport again', () async {
    final c = make();
    await c.read(meshStatusProvider.future);
    await c.read(meshStatusProvider.notifier).refresh();
    verify(() => transport.meshStatus()).called(2);
  });

  test('a master is removable only while it is reachable', () {
    // Removal needs the target to delete its own credentials and say so,
    // so an unreachable one cannot be removed on either transport.
    const online = MeshPeer(uid: 'A', presenceRaw: 'online');
    const offline = MeshPeer(uid: 'B', presenceRaw: 'offline');
    const flapping = MeshPeer(uid: 'C', presenceRaw: 'intermittent');
    expect(online.removable, isTrue);
    expect(offline.removable, isFalse);
    expect(flapping.removable, isFalse);
  });
}
