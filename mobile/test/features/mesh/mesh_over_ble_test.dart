import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ble/ble_proof.dart';
import 'package:unisync/core/ble/endpoints_ble.dart';

/// Getting out of a home must not depend on the transport the home is
/// built on. Leaving a mesh and removing a master from it were Wi-Fi-only,
/// which made Bluetooth a mode you could drive a whole mesh from and never
/// undo — the dead end the story rules out.
void main() {
  const proof = BleProof(n: 'abcdef0123456789', k: 1, p: '0123456789abcdef');

  test('leaving carries nothing but the proof', () {
    final cmd = BleCommands.leaveMesh(proof);
    expect(cmd['c'], 'mesh_leave');
    expect(cmd['n'], proof.n);
    expect(cmd['k'], proof.k);
    expect(cmd['p'], proof.p);
  });

  test('renaming names the mesh', () {
    final cmd = BleCommands.renameMesh(proof: proof, name: 'Upstairs');
    expect(cmd['c'], 'mesh_rename');
    expect(cmd['name'], 'Upstairs');
  });

  test('a kick names its target', () {
    final cmd = BleCommands.kickFromMesh(proof: proof, uid: '2CEC97F0');
    expect(cmd['c'], 'mesh_kick');
    expect(cmd['uid'], '2CEC97F0');
  });

  // The peer-admin verbs take a `uid` meaning "forward this to that
  // master". These two do not: leaving is this master's own decision, and
  // a kick is issued by the master holding the link *about* another. A
  // forwarded leave would take the wrong master out of the mesh.
  test('leaving is never addressed to a peer', () {
    expect(BleCommands.leaveMesh(proof), isNot(contains('uid')));
  });

  test('renaming is never addressed to a peer', () {
    expect(
      BleCommands.renameMesh(proof: proof, name: 'Upstairs'),
      isNot(contains('uid')),
    );
  });
}
