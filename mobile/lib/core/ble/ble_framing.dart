import 'dart:convert';
import 'dart:typed_data';

/// BLE message framing (BLE spec §Framing). Every message, both
/// directions, is chunked:
///
/// ```
/// [0] chunk index
/// [1] chunk total
/// [2..] payload
/// ```
///
/// Payload is at most 160 bytes/chunk; a single-chunk message starts
/// `00 01`. Chunking is required because a state document exceeds the
/// MTU, and the larger MTU the master requests may be refused — so
/// chunk size adapts to the negotiated MTU (see [payloadForMtu]).
abstract final class BleFraming {
  /// Firmware ceiling: never more than 160 payload bytes per chunk.
  static const maxPayload = 160;

  /// 2 framing header bytes + ~3 bytes ATT write overhead.
  static const _overhead = 5;

  /// Payload bytes per chunk for a negotiated [mtu]. Falls back to the
  /// BLE default (23 → 18 usable) when negotiation is refused, and is
  /// capped at the firmware's 160.
  static int payloadForMtu(int mtu) {
    final usable = mtu - _overhead;
    if (usable < 1) return 18; // pathological; 23-default floor
    return usable.clamp(1, maxPayload);
  }

  /// Splits [payload] into `[index, total, ...payload]` chunks of at
  /// most [maxPayloadBytes] payload bytes each. An empty payload still
  /// produces one `00 01` chunk with no body.
  static List<Uint8List> encode(
    List<int> payload, {
    int maxPayloadBytes = maxPayload,
  }) {
    assert(maxPayloadBytes >= 1);
    if (payload.isEmpty) {
      return [Uint8List.fromList([0, 1])];
    }
    final total = (payload.length + maxPayloadBytes - 1) ~/ maxPayloadBytes;
    assert(total <= 255, 'payload too large to frame in one message');
    final chunks = <Uint8List>[];
    for (var i = 0; i < total; i++) {
      final start = i * maxPayloadBytes;
      final end = (start + maxPayloadBytes).clamp(0, payload.length);
      chunks.add(
        Uint8List.fromList([i, total, ...payload.sublist(start, end)]),
      );
    }
    return chunks;
  }

  /// Convenience: JSON map → UTF-8 → framed chunks.
  static List<Uint8List> encodeJson(
    Map<String, Object?> command, {
    int maxPayloadBytes = maxPayload,
  }) {
    return encode(utf8.encode(jsonEncode(command)),
        maxPayloadBytes: maxPayloadBytes);
  }
}

/// Reassembles chunked BLE messages in order, yielding a complete
/// payload when the last chunk (`index == total - 1`) arrives.
///
/// Enforces ordering and consistent totals; on any anomaly it resets
/// (rather than silently corrupting) so a fresh message can start
/// clean — matching the firmware's "treat every push as a complete
/// snapshot" contract.
class ChunkReassembler {
  final List<int> _buffer = [];
  int _expectedIndex = 0;
  int? _total;

  /// Feeds one raw chunk. Returns the reassembled payload when this
  /// chunk completes a message, else null. Malformed/out-of-order
  /// chunks reset the assembler and return null.
  Uint8List? add(List<int> chunk) {
    if (chunk.length < 2) {
      _reset();
      return null;
    }
    final index = chunk[0];
    final total = chunk[1];
    final payload = chunk.sublist(2);

    if (total < 1) {
      _reset();
      return null;
    }

    // A first chunk (index 0) always starts a fresh message.
    if (index == 0) {
      _buffer
        ..clear()
        ..addAll(payload);
      _total = total;
      _expectedIndex = 1;
      if (total == 1) {
        final out = Uint8List.fromList(_buffer);
        _reset();
        return out;
      }
      return null;
    }

    // Continuation must match the in-progress message exactly.
    if (_total == null || total != _total || index != _expectedIndex) {
      _reset();
      return null;
    }

    _buffer.addAll(payload);
    _expectedIndex++;

    if (index == total - 1) {
      final out = Uint8List.fromList(_buffer);
      _reset();
      return out;
    }
    return null;
  }

  /// Reassembled payload decoded as a JSON map, or null if the message
  /// isn't complete or isn't a JSON object.
  Map<String, Object?>? addJson(List<int> chunk) {
    final payload = add(chunk);
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  void _reset() {
    _buffer.clear();
    _expectedIndex = 0;
    _total = null;
  }
}
