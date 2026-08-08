import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Optimistic overlay for switch toggles.
///
/// Tapping a tile records the intended state here; the tile renders
/// the override immediately while POST /api/relay is in flight. The
/// next WebSocket snapshot is authoritative (API §4) and clears the
/// override — whether it confirms or contradicts the tap. A failed
/// POST clears it too, snapping the tile back.
final switchOverridesProvider =
    NotifierProvider<SwitchOverridesNotifier, Map<String, bool>>(
  SwitchOverridesNotifier.new,
);

class SwitchOverridesNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void set(String id, bool on) => state = {...state, id: on};

  void clear(String id) {
    if (!state.containsKey(id)) return;
    final next = {...state}..remove(id);
    state = next;
  }

  void clearAll() => state = const {};
}
