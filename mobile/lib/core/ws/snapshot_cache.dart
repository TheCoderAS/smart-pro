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

  /// Records a live snapshot. Cheap enough to do on every arrival: the
  /// document is a few KB and writes are already batched by the platform.
  Future<void> save(StateSnapshot snap) async {
    state = snap;
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
