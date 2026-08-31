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
    this.meshName,
  });

  factory SavedMaster.fromJson(Map<String, dynamic> json) => SavedMaster(
        uid: json['uid'] as String? ?? '',
        name: json['name'] as String? ?? '',
        ssid: json['ssid'] as String?,
        meshId: json['meshId'] as int?,
        meshName: json['meshName'] as String?,
      );

  final String uid;
  final String name;

  /// The AP's SSID, when known — used to auto-join on switch.
  final String? ssid;

  /// The BLE mesh id (BLE spec §Discovery). Used to filter BLE scans to
  /// this home. Null until learned; 0 = standalone.
  final int? meshId;

  /// The mesh's display name, cached so screens can name the home
  /// ("Disconnect UnisyncMesh") on either transport and offline.
  final String? meshName;

  /// True only for a real, non-zero mesh id. Zero and null are
  /// standalone and match nothing — the rule the whole BLE trust check
  /// rests on.
  bool get inMesh => meshId != null && meshId != 0;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        if (ssid != null) 'ssid': ssid,
        if (meshId != null) 'meshId': meshId,
        if (meshName != null) 'meshName': meshName,
      };
}

final masterRegistryProvider =
    AsyncNotifierProvider<MasterRegistryNotifier, List<SavedMaster>>(
  MasterRegistryNotifier.new,
);

class MasterRegistryNotifier extends AsyncNotifier<List<SavedMaster>> {
  static const _key = 'masters';
  static const _lastUsedKey = 'masters.lastUsed';

  /// uids [ensure] has already declined to add. Keeps the refusal to one
  /// line per master per launch instead of one per state push.
  final _refused = <String>{};

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

  /// Refreshes the name/network of an ALREADY-ADDED master. Never adds.
  ///
  /// The single-writer rule, learned the hard way: this used to add a
  /// master when the list was empty, which let a stale status update —
  /// in flight while the user removed their switch — quietly write the
  /// removed master straight back in. The next sign-in's registration
  /// was then refused ("unknown master"), Wi-Fi worked (it never reads
  /// this list) and Bluetooth hunted the ghost. Adding happens through
  /// [setHome], from sign-in, and nowhere else.
  Future<void> ensure({
    required String uid,
    String? name,
    String? ssid,
  }) async {
    if (uid.isEmpty) return;
    final current = [...state.value ?? await _load()];
    final i = current.indexWhere((m) => m.uid == uid);
    if (i < 0) {
      // Once per uid, not once per call. In a mesh the dashboard sees a
      // peer's state push about once a second, and each one used to add
      // a line here — the log a user opens to diagnose something else
      // was drowned in this single sentence.
      if (_refused.add(uid)) {
        log.d('not recording $uid: only sign-in adds a switch');
      }
      return;
    }
    _refused.remove(uid);
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
      meshName: m.meshName,
    );
    await _persist(current);
  }

  /// Records what the master says about its own mesh membership, from
  /// `/api/info` over Wi-Fi. Authoritative in BOTH directions: it sets
  /// the mesh id when the master is meshed and CLEARS it when it is not,
  /// so a master that left a mesh stops vouching for its old mates.
  ///
  /// Like [ensure] this never adds — only sign-in adds a switch. And
  /// like [ensure] it is a no-op when nothing changed, which is every
  /// call in a standalone home (null → null).
  Future<void> setMesh({
    required String uid,
    required bool inMesh,
    required int meshId,
    required String meshName,
  }) async {
    if (uid.isEmpty) return;
    final current = [...state.value ?? await _load()];
    final i = current.indexWhere((m) => m.uid == uid);
    if (i < 0) return;
    final m = current[i];
    // A meshed master with a zero id is a firmware that hasn't finished
    // deriving one; leave what we had rather than half-clearing.
    if (inMesh && meshId == 0) return;
    final nextId = inMesh ? meshId : null;
    final nextName = inMesh && meshName.isNotEmpty ? meshName : null;
    if (nextId == m.meshId && nextName == m.meshName) return;
    log.i(inMesh
        ? 'mesh: ${m.uid} is in "$nextName" '
            '(0x${meshId.toRadixString(16)})'
        : 'mesh: ${m.uid} is standalone — mesh id cleared');
    current[i] = SavedMaster(
      uid: m.uid,
      name: m.name,
      ssid: m.ssid,
      meshId: nextId,
      meshName: nextName,
    );
    await _persist(current);
  }

  /// THE one way a switch is added: a successful sign-in. Replaces the
  /// list with exactly this master — unconditional, so no ghost entry
  /// (however it got there) can ever refuse or outrank the switch the
  /// user just proved they own with a password.
  Future<void> setHome(SavedMaster master) async {
    log.i('home = ${master.uid} "${master.name}" (set by sign-in)');
    await _persist([master]);
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
