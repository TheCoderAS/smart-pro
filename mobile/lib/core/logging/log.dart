import 'package:logger/logger.dart';

import 'log_buffer.dart';

/// App-wide logger. Nothing here ever leaves the device — no telemetry,
/// no crash SaaS.
///
/// The level is debug in both modes now, and the *output* decides what
/// reaches the console: quiet in release, as before. That change is what
/// lets the in-app log screen show something useful on the release build
/// someone is actually running, instead of only on a debug build attached
/// to a laptop. A filtered-out line never reaches the output at all, so
/// gating at the level would have left the buffer empty where it matters.
final log = Logger(
  // ProductionFilter, explicitly. The package's default DevelopmentFilter
  // drops EVERY event in a release build before it reaches the output —
  // its shouldLog lives inside an assert. Setting the level and output
  // was not enough: the Logs screen shipped empty on exactly the build
  // it was made for, because the filter in front of the output was never
  // consulted about any of this.
  filter: ProductionFilter(),
  level: Level.debug,
  printer: PrettyPrinter(
    methodCount: 0,
    dateTimeFormat: DateTimeFormat.onlyTime,
  ),
  output: BufferedConsoleOutput(),
);
