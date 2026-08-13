import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/log.dart';
import 'state_dto.dart';

/// The last state the master pushed, kept on disk.
///
/// Opening the app should show the house immediately, not a spinner while a
/// probe and a radio connection complete — someone reaching for their phone
/// in the dark is the case that matters. The cached snapshot paints at
/// once; because the link isn't confirmed yet, [LinkState] keeps the
/// controls disabled and the states labelled "last seen" until it is. So
/// this is fast *and* honest: you see the house right away, and you can't
/// tap something on the strength of a stale value.
///
/// Never authoritative. Every live snapshot replaces it wholesale, exactly
/// as the live ones replace each other.
final snapshotCacheProvider =
    NotifierProvider<SnapshotCacheNotifier, StateSnapshot?>(
  SnapshotCacheNotifier.new,
);

class SnapshotCacheNotifier extends Notifier<StateSnapshot?> {
  static const key = 'state.lastSnapshot';

  @override
  StateSnapshot? build() {
    ref.onDispose(() => _writeTimer?.cancel());
    Future.microtask(_restore);
    return null;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      // Only if nothing live has landed in the meantime — a cold start can
      // race a fast connection, and the live one always wins.
      if (state == null) state = StateSnapshot.fromJson(decoded);
    } on Object catch (e) {
      log.w('snapshot cache unreadable: $e');
    }
  }

  /// How long a write waits for the pushes behind it to stop arriving.
  static const writeAfter = Duration(seconds: 3);

  Timer? _writeTimer;
  StateSnapshot? _unwritten;

  /// Records a live snapshot.
  ///
  /// In memory immediately — that is what the UI reads. The disk write is
  /// debounced, because "cheap enough to do on every arrival" (my words,
  /// and wrong) meant a JSON encode plus a SharedPreferences write for
  /// every push the master sent. The master pushes on a 150 ms floor, so a
  /// burst of activity turned into a burst of writes on the same platform
  /// channel machinery the BLE plugin is using — competing with the very
  /// commands the user is waiting on.
  ///
  /// Losing the last few seconds of cache to a kill costs one stale paint
  /// on next launch, which the "last seen" labelling already covers.
  void save(StateSnapshot snap) {
    state = snap;
    _unwritten = snap;
    _writeTimer?.cancel();
    _writeTimer = Timer(writeAfter, flush);
  }

  /// Writes anything still pending now. Called by the debounce timer, and
  /// available to anyone that wants the cache durable at a known point.
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    final snap = _unwritten;
    if (snap == null) return;
    _unwritten = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(snap.toJson()));
    } on Object catch (e) {
      log.w('snapshot cache not written: $e');
    }
  }

  /// Dropped when a master is removed from the app, so the next launch
  /// doesn't flash a house that is no longer yours.
  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
