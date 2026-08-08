import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ws/state_dto.dart';

/// Optimistic overlay for switch toggles.
///
/// Tapping a tile records the intended state here; the tile renders the
/// override immediately while the command is in flight. An override is
/// held until a snapshot **confirms** it (the reported state matches),
/// then cleared — so an intermediate/stale snapshot arriving before the
/// firmware has applied the change (notably after "All off") doesn't
/// flicker the tile back. A failed command clears it immediately, and a
/// safety timeout drops any override that is never confirmed.
final switchOverridesProvider =
    NotifierProvider<SwitchOverridesNotifier, Map<String, bool>>(
  SwitchOverridesNotifier.new,
);

class SwitchOverridesNotifier extends Notifier<Map<String, bool>> {
  static const _timeout = Duration(seconds: 8);
  final _timers = <String, Timer>{};

  @override
  Map<String, bool> build() {
    ref.onDispose(_cancelTimers);
    return const {};
  }

  void set(String id, bool on) {
    state = {...state, id: on};
    _timers[id]?.cancel();
    _timers[id] = Timer(_timeout, () => clear(id));
  }

  void clear(String id) {
    _timers.remove(id)?.cancel();
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }

  void clearAll() {
    _cancelTimers();
    if (state.isNotEmpty) state = const {};
  }

  /// Reconcile overrides against an authoritative snapshot: drop the
  /// ones the snapshot confirms (or that no longer exist), keep the ones
  /// it still contradicts so the tile stays on its intended state until
  /// the firmware catches up.
  void reconcile(List<SwitchState> switches) {
    if (state.isEmpty) return;
    final reported = {for (final s in switches) s.id: s.on};
    final next = {...state};
    for (final entry in state.entries) {
      final actual = reported[entry.key];
      if (actual == null || actual == entry.value) {
        next.remove(entry.key);
        _timers.remove(entry.key)?.cancel();
      }
    }
    if (next.length != state.length) state = next;
  }

  void _cancelTimers() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
