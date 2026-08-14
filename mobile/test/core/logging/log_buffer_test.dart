import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/logging/log_buffer.dart';

void main() {
  test('keeps the newest lines and drops the oldest', () {
    final buf = LogBuffer(capacity: 10);
    for (var i = 0; i < 500; i++) {
      buf.add('line $i');
    }
    // Trimming is batched, so the bound is capacity plus one batch —
    // what matters is that it stays bounded and keeps the tail.
    expect(buf.lines.length, lessThanOrEqualTo(110));
    expect(buf.lines.last, 'line 499');
  });

  test('notifies so an open screen redraws', () {
    final buf = LogBuffer();
    final before = buf.revision.value;
    buf.add('something happened');
    expect(buf.revision.value, greaterThan(before));
  });

  test('copy gives one line per entry', () {
    final buf = LogBuffer();
    buf.add('first');
    buf.add('second');
    expect(buf.asText(), 'first\nsecond');
  });

  test('clearing empties it', () {
    final buf = LogBuffer();
    buf.add('gone soon');
    buf.clear();
    expect(buf.isEmpty, isTrue);
    expect(buf.asText(), isEmpty);
  });
}
