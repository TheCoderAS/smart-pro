import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/log.dart';

/// A master the user has added to the app. Non-secret bookkeeping —
/// tokens and remembered passwords live in SecureStore, keyed by uid.
class SavedMaster {
  const SavedMaster({
    required this.uid,
    required this.name,
    this.ssid,
    this.meshId,
  });

  factory SavedMaster.fromJson(Map<String, dynamic> json) => SavedMaster(
        uid: json['uid'] as String? ?? '',
        name: json['name'] as String? ?? '',
        ssid: json['ssid'] as String?,
        meshId: json['meshId'] as int?,
      );

  final String uid;
  final String name;

  /// The AP's SSID, when known — used to auto-join on switch.
  final String? ssid;

  /// The BLE mesh id (BLE spec §Discovery), captured at pairing. Used
  /// to filter BLE scans to this system. Null until learned; 0 =
  /// standalone.
  final int? meshId;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        if (ssid != null) 'ssid': ssid,
        if (meshId != null) 'meshId': meshId,
      };
}

final masterRegistryProvider =
    AsyncNotifierProvider<MasterRegistryNotifier, List<SavedMaster>>(
  MasterRegistryNotifier.new,
);

class MasterRegistryNotifier extends AsyncNotifier<List<SavedMaster>> {
  static const _key = 'masters';
  static const _lastUsedKey = 'masters.lastUsed';

  /// Bookkeeping only — uid, display name, cached network name, mesh id.
  /// The secrets the vault exists to protect (tokens, remembered
  /// passwords) live in [SecureStore] and never touch this file.
  @override
  Future<List<SavedMaster>> build() => _load();

  Future<List<SavedMaster>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    final all = [
      for (final e in list)
        if (e is Map<String, dynamic>) SavedMaster.fromJson(e),
    ];
    return _oneHome(all);
  }

  /// One device per app: the first entry and, when it is meshed, its
  /// mesh-mates. Anything else is pruned — including entries left over
  /// from when the app allowed several devices.
  static List<SavedMaster> _oneHome(List<SavedMaster> all) {
    if (all.length <= 1) return all;
    final home = all.first;
    final mesh = home.meshId;
    final kept = [
      for (final m in all)
        if (m.uid == home.uid || (mesh != null && mesh != 0 && m.meshId == mesh))
          m,
    ];
    if (kept.length != all.length) {
      log.w('registry pruned to one home '
          '(${all.length} entries -> ${kept.length})');
    }
    return kept;
  }

  Future<void> _persist(List<SavedMaster> masters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final m in masters) m.toJson()]),
    );
    state = AsyncValue.data(masters);
  }

  /// Records a master seen on a live connection (any transport),
  /// keeping any existing `ssid`/`meshId` and only refreshing the name.
  /// Called from the dashboard on every state snapshot so a master the
  /// user signed into — not just one commissioned from scratch — is
  /// known to the BLE cold-start path. No-op when nothing changes.
  Future<void> ensure({
    required String uid,
    String? name,
    String? ssid,
  }) async {
    if (uid.isEmpty) return;
    final current = [...state.value ?? await _load()];
    final i = current.indexWhere((m) => m.uid == uid);
    // Only what the user added is ever recorded. The old rule quietly
    // adopted any unknown uid as long as the home was meshed — which is
    // how a removed master could creep back into the books. Mesh mates
    // are accepted per-connection by the transport identity checks; they
    // do not need a registry entry to be controlled.
    if (i < 0 && current.isNotEmpty) {
      log.w('ignoring unknown master $uid: not added to this app');
      return;
    }
    if (i >= 0) {
      final m = current[i];
      final nextName = (name?.isNotEmpty ?? false) ? name! : m.name;
      // The network name is cached from the master's own report every time
      // we are connected, so instruction copy heals itself after a rename.
      final nextSsid = (ssid?.isNotEmpty ?? false) ? ssid : m.ssid;
      if (nextName == m.name && nextSsid == m.ssid) return;
      current[i] = SavedMaster(
        uid: m.uid,
        name: nextName,
        ssid: nextSsid,
        meshId: m.meshId,
      );
    } else {
      current.add(
        SavedMaster(
          uid: uid,
          name: (name?.isNotEmpty ?? false) ? name! : 'Master',
          ssid: (ssid?.isNotEmpty ?? false) ? ssid : null,
        ),
      );
    }
    await _persist(current);
  }

  /// Adds or updates (by uid).
  Future<void> upsert(SavedMaster master) async {
    final current = [...state.value ?? await _load()];
    final i = current.indexWhere((m) => m.uid == master.uid);
    if (i >= 0) {
      current[i] = master;
    } else {
      current.add(master);
    }
    await _persist(current);
  }

  /// Forgets everything — "set up a different switch". Secrets are the
  /// caller's to purge (SecureStore), this is only the bookkeeping.
  Future<void> clear() => _persist(const []);

  Future<void> remove(String uid) async {
    final current = [...state.value ?? await _load()]
      ..removeWhere((m) => m.uid == uid);
    await _persist(current);
  }

  Future<void> setLastUsed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsedKey, uid);
  }

  Future<String?> lastUsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastUsedKey);
  }
}
