import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// The last few hundred log lines, kept in memory so they can be read on
/// the phone.
///
/// Diagnosing anything on real hardware meant tethering to a laptop and
/// running `adb logcat`, which is friction paid on every round of testing —
/// and impossible when the phone is the only thing to hand. This keeps the
/// same lines the console gets, so Settings can show them and offer a copy
/// button.
///
/// Memory only: never written to disk, never sent anywhere. It dies with
/// the process, which is the right lifetime for something that exists to
/// answer "what just happened".
class LogBuffer {
  LogBuffer({this.capacity = 500});

  final int capacity;
  final List<String> _lines = [];

  /// Bumped on every append so a screen can rebuild without polling.
  final revision = ValueNotifier<int>(0);

  List<String> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;

  void add(String line) {
    _lines.add(line);
    // Trim generously rather than one at a time: removeAt(0) on a List is
    // O(n), and this runs on the logging path.
    if (_lines.length > capacity + 100) {
      _lines.removeRange(0, _lines.length - capacity);
    }
    revision.value++;
  }

  void clear() {
    _lines.clear();
    revision.value++;
  }

  String asText() => _lines.join('\n');
}

final logBuffer = LogBuffer();

/// Fans log lines to the console and to [logBuffer].
///
/// The buffer takes everything, including debug lines, even in release —
/// the whole point is that a release build on a bench can still say what it
/// did. The console stays quiet in release, as before.
class BufferedConsoleOutput extends LogOutput {
  /// PrettyPrinter draws a box around each entry. Useful in a terminal,
  /// noise in a text field someone is about to paste into a message.
  static final _boxChars = RegExp(r'^[│┌└├─┐┘┤┬┴┼\s]*');
  static final _ansi = RegExp(r'\x1B\[[0-9;]*m');

  @override
  void output(OutputEvent event) {
    final quiet = kReleaseMode && event.level.index < Level.warning.index;
    for (final line in event.lines) {
      if (!quiet) {
        // ignore: avoid_print
        print(line);
      }
      final plain = line.replaceAll(_ansi, '').replaceFirst(_boxChars, '');
      if (plain.trim().isEmpty) continue;
      logBuffer.add(plain);
    }
  }
}
