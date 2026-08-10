import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ble/ble_proof.dart';
import 'package:unisync/core/ble/endpoints_ble.dart';

void main() {
  // Handover §1: token used as ASCII bytes; counter appended to the
  // 8-byte nonce as 4 bytes big-endian; proof is the first 8 bytes of
  // HMAC-SHA256, hex encoded.
  const token = '518e625b45fcd138cd9e06dc802384a6';
  const nonce = [0x3f, 0x2a, 0x8c, 0x11, 0xd4, 0xe0, 0x7b, 0x62];

  String expectedProof(int counter) {
    final msg = <int>[
      ...nonce,
      (counter >> 24) & 0xFF,
      (counter >> 16) & 0xFF,
      (counter >> 8) & 0xFF,
      counter & 0xFF,
    ];
    final mac = Hmac(sha256, utf8.encode(token)).convert(msg).bytes;
    return [
      for (final b in mac.sublist(0, 8)) b.toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  test('n is the first 16 hex chars of the token', () {
    final proof =
        computeBleProof(token: token, sessionNonce: nonce, counter: 1);
    expect(proof.n, '518e625b45fcd138');
    expect(proof.n.length, 16);
  });

  test('p matches HMAC-SHA256(token, nonce ‖ counter)[0..7] as hex', () {
    for (final k in [1, 2, 255, 256, 65536, 16777216]) {
      final proof =
          computeBleProof(token: token, sessionNonce: nonce, counter: k);
      expect(proof.p, expectedProof(k), reason: 'counter $k');
      expect(proof.p.length, 16, reason: '8 bytes hex');
      expect(proof.k, k);
    }
  });

  test('the counter changes the proof — replays cannot be reused', () {
    final a = computeBleProof(token: token, sessionNonce: nonce, counter: 1);
    final b = computeBleProof(token: token, sessionNonce: nonce, counter: 2);
    expect(a.p, isNot(b.p));
  });

  test('a new session nonce changes the proof for the same counter', () {
    final a = computeBleProof(token: token, sessionNonce: nonce, counter: 1);
    final b = computeBleProof(
      token: token,
      sessionNonce: const [1, 2, 3, 4, 5, 6, 7, 8],
      counter: 1,
    );
    expect(a.p, isNot(b.p));
  });

  test('commands carry n/k/p and never the raw token', () {
    final proof =
        computeBleProof(token: token, sessionNonce: nonce, counter: 7);
    final cmd = BleCommands.relay(proof: proof, id: 'ext0_1', on: true);

    expect(cmd['n'], proof.n);
    expect(cmd['k'], 7);
    expect(cmd['p'], proof.p);
    expect(cmd['c'], 'relay');
    expect(cmd['id'], 'ext0_1');
    expect(cmd['s'], true);

    // The whole encoded command must not contain the token.
    expect(jsonEncode(cmd).contains(token), isFalse);
    expect(cmd.containsKey('t'), isFalse);
  });

  test('every command builder carries the proof and no token', () {
    final proof =
        computeBleProof(token: token, sessionNonce: nonce, counter: 3);
    final commands = <Map<String, Object?>>[
      BleCommands.killAll(proof),
      BleCommands.state(proof),
      BleCommands.extensions(proof),
      BleCommands.fwList(proof),
      BleCommands.mesh(proof),
      BleCommands.reorder(proof: proof, order: 'ext0_1,master_1'),
      BleCommands.renameExtension(proof: proof, slot: 0, name: 'Bedroom'),
      BleCommands.renameSwitch(proof: proof, id: 'ext0_1', name: 'Lamp'),
      BleCommands.renameMaster(proof: proof, name: 'Hall'),
    ];
    for (final cmd in commands) {
      expect(cmd['p'], proof.p, reason: '${cmd['c']} carries the proof');
      expect(cmd.containsKey('t'), isFalse, reason: '${cmd['c']} has no token');
      expect(jsonEncode(cmd).contains(token), isFalse);
    }
  });
}
