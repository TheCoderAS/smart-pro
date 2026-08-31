import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ble/ble_proof.dart';
import 'package:unisync/core/ble/endpoints_ble.dart';

/// Admin in a mesh has to reach any master, not just the one holding the
/// Bluetooth link. The master forwards what isn't its own — but only if
/// the app actually says who it means, so the uid field is the contract.
void main() {
  const proof = BleProof(n: 'abcdef0123456789', k: 1, p: '0123456789abcdef');
  const peer = '2CEC97F0';

  group('a peer uid rides along', () {
    test('rename master', () {
      final cmd = BleCommands.renameMaster(
        proof: proof,
        name: 'Hall',
        masterUid: peer,
      );
      expect(cmd['c'], 'rename_master');
      expect(cmd['uid'], peer);
    });

    test('rename switch', () {
      final cmd = BleCommands.renameSwitch(
        proof: proof,
        id: 'ext0_1',
        name: 'Lamp',
        masterUid: peer,
      );
      expect(cmd['c'], 'rename_sw');
      expect(cmd['uid'], peer);
    });

    test('reorder', () {
      final cmd = BleCommands.reorder(
        proof: proof,
        order: 'a,b,c',
        masterUid: peer,
      );
      expect(cmd['c'], 'reorder');
      expect(cmd['uid'], peer);
    });

    test('restore policy', () {
      final cmd = BleCommands.setRestore(
        proof: proof,
        id: 'master_1',
        restore: true,
        masterUid: peer,
      );
      expect(cmd['c'], 'set_restore');
      expect(cmd['uid'], peer);
    });

    test('cleanup dead extension slots', () {
      final cmd = BleCommands.cleanupExtensions(
        proof: proof,
        masterUid: peer,
      );
      expect(cmd['c'], 'cleanup_exts');
      expect(cmd['uid'], peer);
    });
  });

  // The uid must be ABSENT, not empty: the firmware treats any non-empty
  // uid as "forward this", and an empty string would have it hunt for a
  // peer that does not exist instead of acting on itself.
  group('no uid means the master we are talking to', () {
    test('omitted entirely when null', () {
      expect(
        BleCommands.renameMaster(proof: proof, name: 'Hall'),
        isNot(contains('uid')),
      );
      expect(
        BleCommands.reorder(proof: proof, order: 'a,b'),
        isNot(contains('uid')),
      );
      expect(
        BleCommands.cleanupExtensions(proof: proof),
        isNot(contains('uid')),
      );
    });

    test('omitted when empty', () {
      expect(
        BleCommands.renameSwitch(
          proof: proof,
          id: 'master_1',
          name: 'Lamp',
          masterUid: '',
        ),
        isNot(contains('uid')),
      );
    });
  });

  test('every command still carries its proof', () {
    final cmd = BleCommands.cleanupExtensions(proof: proof, masterUid: peer);
    expect(cmd['n'], proof.n);
    expect(cmd['k'], proof.k);
    expect(cmd['p'], proof.p);
  });
}
