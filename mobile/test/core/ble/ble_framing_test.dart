import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ble/ble_framing.dart';

void main() {
  group('payloadForMtu', () {
    test('adapts to MTU, capped at 160', () {
      expect(BleFraming.payloadForMtu(23), 18); // default MTU
      expect(BleFraming.payloadForMtu(185), 160); // large → capped
      expect(BleFraming.payloadForMtu(100), 95);
    });
    test('pathological MTU floors at 18', () {
      expect(BleFraming.payloadForMtu(3), 18);
    });
  });

  group('encode', () {
    test('single-chunk message starts 00 01', () {
      final chunks = BleFraming.encode([1, 2, 3]);
      expect(chunks, hasLength(1));
      expect(chunks.first[0], 0);
      expect(chunks.first[1], 1);
      expect(chunks.first.sublist(2), [1, 2, 3]);
    });

    test('empty payload still frames as 00 01', () {
      final chunks = BleFraming.encode([]);
      expect(chunks, hasLength(1));
      expect(chunks.first, [0, 1]);
    });

    test('splits at the payload boundary', () {
      final payload = List<int>.generate(400, (i) => i % 256);
      final chunks = BleFraming.encode(payload);
      expect(chunks, hasLength(3)); // 160 + 160 + 80
      expect(chunks[0][0], 0);
      expect(chunks[0][1], 3);
      expect(chunks[1][0], 1);
      expect(chunks[2][0], 2);
      expect(chunks[2].length - 2, 80);
    });
  });

  group('ChunkReassembler', () {
    test('single-chunk round-trip', () {
      final r = ChunkReassembler();
      final out = r.add([0, 1, 9, 8, 7]);
      expect(out, [9, 8, 7]);
    });

    test('multi-chunk reassembly in order', () {
      final payload = List<int>.generate(400, (i) => i % 256);
      final chunks = BleFraming.encode(payload);
      final r = ChunkReassembler();
      expect(r.add(chunks[0]), isNull);
      expect(r.add(chunks[1]), isNull);
      expect(r.add(chunks[2]), payload);
    });

    test('out-of-order chunk resets assembly', () {
      final r = ChunkReassembler();
      expect(r.add([0, 3, 1]), isNull);
      // Skip index 1, jump to 2 → reset, no output.
      expect(r.add([2, 3, 3]), isNull);
    });

    test('mismatched total resets', () {
      final r = ChunkReassembler();
      expect(r.add([0, 3, 1]), isNull);
      expect(r.add([1, 4, 2]), isNull); // total changed 3→4
    });

    test('a new index-0 chunk abandons a partial message', () {
      final r = ChunkReassembler();
      expect(r.add([0, 3, 1]), isNull); // partial
      // Fresh single-chunk message arrives.
      expect(r.add([0, 1, 42]), [42]);
    });

    test('too-short chunk resets and returns null', () {
      final r = ChunkReassembler();
      expect(r.add([0]), isNull);
    });

    test('addJson decodes a completed JSON object', () {
      final payload = utf8.encode(jsonEncode({'ok': true, 'v': 3}));
      final chunks = BleFraming.encode(payload, maxPayloadBytes: 4);
      final r = ChunkReassembler();
      Map<String, Object?>? result;
      for (final c in chunks) {
        result = r.addJson(c);
      }
      expect(result, {'ok': true, 'v': 3});
    });

    test('a >MTU JSON state document survives the round-trip', () {
      final doc = {
        'master_name': 'Living Room',
        'switches': [
          for (var i = 0; i < 12; i++)
            {'id': 'ext${i}_1', 'name': 'Switch $i', 'on': i.isEven},
        ],
      };
      final chunks = BleFraming.encodeJson(doc, maxPayloadBytes: 18);
      expect(chunks.length, greaterThan(1)); // exceeds a small MTU
      final r = ChunkReassembler();
      Map<String, Object?>? out;
      for (final c in chunks) {
        out = r.addJson(c);
      }
      expect(out, doc);
    });
  });
}
