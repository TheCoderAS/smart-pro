import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// App-wide logger. Verbose in debug, warnings-and-up in release.
/// Nothing here ever leaves the device — no telemetry, no crash SaaS.
final log = Logger(
  level: kReleaseMode ? Level.warning : Level.debug,
  printer: PrettyPrinter(
    methodCount: 0,
    dateTimeFormat: DateTimeFormat.onlyTime,
  ),
);
