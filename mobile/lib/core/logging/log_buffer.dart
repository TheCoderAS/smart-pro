import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// The last few hundred log lines, kept in memory so they can be read on
/// the phone — and mirrored to a small file so a CRASH cannot eat the
/// evidence.
///
/// Diagnosing anything on real hardware meant tethering to a laptop and
/// running `adb logcat`, which is friction paid on every round of testing —
/// and impossible when the phone is the only thing to hand. This keeps the
/// same lines the console gets, so Settings can show them and offer a copy
/// button.
///
/// The mirror exists because a memory-only buffer dies with the process:
/// the one time the log matters most — the app crashed — the Logs screen
/// opened on a fresh, empty buffer. Now the previous run's tail is loaded
/// back on startup, marked as such. Never sent anywhere; lives in the
/// app's own cache directory.
class LogBuffer {
  LogBuffer({this.capacity = 500});

  final int capacity;
  final List<String> _lines = [];

  /// Debounced disk mirror: cheap enough to survive the logging path,
  /// fresh enough (2 s) that a crash loses only its final moments.
  static const _writeAfter = Duration(seconds: 2);
  Timer? _writeTimer;
  File? _mirror;
  bool _restored = false;

  /// Loads the previous run's tail (marked) and starts mirroring. Called
  /// once from main(); everything is best-effort — logging must never be
  /// the thing that breaks.
  Future<void> restoreAndMirror() async {
    if (_restored) return;
    _restored = true;
    try {
      // On Android, systemTemp is the app's own cache dir.
      final f = File('${Directory.systemTemp.path}/unisync_log_tail.txt');
      if (f.existsSync()) {
        final previous = f
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .toList();
        if (previous.isNotEmpty) {
          _lines.insertAll(0, [
            ...previous.map((l) => '· $l'),
            '—— previous run ended above (crash or kill) ——',
          ]);
          revision.value++;
        }
      }
      _mirror = f;
    } on Object catch (_) {
      // No cache dir, no mirror — in-memory behaviour as before.
    }
  }

  void _scheduleWrite() {
    final f = _mirror;
    if (f == null) return;
    _writeTimer?.cancel();
    _writeTimer = Timer(_writeAfter, () {
      try {
        // Only this run's lines: previous-run lines are marked with '·'
        // and must not survive a second restart as fresh evidence.
        final own =
            _lines.where((l) => !l.startsWith('· ') && !l.startsWith('——'));
        f.writeAsStringSync(own.join('\n'));
      } on Object catch (_) {
        // Disk full or gone — the in-memory buffer still works.
      }
    });
  }

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
    _scheduleWrite();
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
