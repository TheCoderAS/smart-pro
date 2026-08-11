import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ws/state_dto.dart';

/// One master's slice of the dashboard: its identity and its switches.
class MasterSection {
  const MasterSection({
    required this.uid,
    required this.name,
    required this.switches,
    required this.isSelf,
    required this.presence,
    required this.lastSeen,
  });

  final String uid;
  final String name;
  final List<SwitchState> switches;

  /// True for the master the app is talking to. Its switches are driven
  /// directly; everyone else's are relayed across the mesh.
  final bool isSelf;

  final Presence presence;
  final int lastSeen;

  bool get online => presence == Presence.online;

  /// What to pass as the relay's owning master.
  ///
  /// Null for the master we're actually connected to: its relays are driven
  /// directly. Sending its own uid instead routes the command through the
  /// mesh relay endpoint, which looks the uid up in the *peer* table, fails
  /// to find it, and 404s — so nothing switches at all. Deriving it here
  /// means no call site can get it wrong.
  String? get relayUid => isSelf ? null : uid;
}

/// Splits a snapshot into per-master sections, in the user's card order.
///
/// A standalone master yields exactly one section, which is why the mesh
/// dashboard and the standalone dashboard are the same screen.
List<MasterSection> sectionsFrom(StateSnapshot snap, List<String> order) {
  final sections = <MasterSection>[
    MasterSection(
      uid: snap.selfUid,
      name: snap.masterName.isEmpty ? 'This switch' : snap.masterName,
      // Offline extensions' switches leave the dashboard (Epic 2).
      switches: snap.switches.where((s) => s.online).toList(growable: false),
      isSelf: true,
      presence: Presence.online,
      lastSeen: 0,
    ),
    for (final p in snap.peers)
      MasterSection(
        uid: p.uid,
        name: p.name.isEmpty ? p.uid : p.name,
        switches: p.switches.where((s) => s.online).toList(growable: false),
        isSelf: false,
        presence: p.presence,
        lastSeen: p.lastSeen,
      ),
  ];

  if (order.isEmpty) return sections;
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  sections.sort((a, b) {
    final ra = rank[a.uid] ?? 1 << 30;
    final rb = rank[b.uid] ?? 1 << 30;
    if (ra != rb) return ra.compareTo(rb);
    // Unranked masters keep their arrival order, self first.
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    return 0;
  });
  return sections;
}

/// Card order, by master uid.
///
/// Deliberately app-local and not synced: different people in a house want
/// their own nearest master on top, and the story makes this the one
/// intentional exception to "the master owns all ordering truth". It does
/// not survive a reinstall, by design.
final masterCardOrderProvider =
    NotifierProvider<MasterCardOrderNotifier, List<String>>(
  MasterCardOrderNotifier.new,
);

class MasterCardOrderNotifier extends Notifier<List<String>> {
  static const key = 'dashboard.masterOrder';

  @override
  List<String> build() {
    Future.microtask(_restore);
    return const [];
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(key);
    if (saved != null && saved.isNotEmpty) state = saved;
  }

  Future<void> set(List<String> uids) async {
    state = uids;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, uids);
  }
}

/// Which master's card is open. One at a time: expanding a card collapses
/// the previous one, so a mesh dashboard stays readable however many
/// masters are in the house.
final expandedMasterProvider =
    NotifierProvider<ExpandedMasterNotifier, String?>(
  ExpandedMasterNotifier.new,
);

class ExpandedMasterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Tapping the open card closes it; tapping another opens that one.
  void toggle(String uid) => state = (state == uid) ? null : uid;

  /// Opens [uid] if nothing is open yet — used to expand the first card on
  /// arrival so a standalone user never sees a collapsed dashboard.
  void defaultTo(String uid) {
    if (state == null) state = uid;
  }
}
