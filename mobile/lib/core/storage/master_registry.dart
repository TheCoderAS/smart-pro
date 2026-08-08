import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A master the user has added to the app. Non-secret bookkeeping —
/// tokens and remembered passwords live in SecureStore, keyed by uid.
class SavedMaster {
  const SavedMaster({
    required this.uid,
    required this.name,
    this.ssid,
  });

  factory SavedMaster.fromJson(Map<String, dynamic> json) => SavedMaster(
        uid: json['uid'] as String? ?? '',
        name: json['name'] as String? ?? '',
        ssid: json['ssid'] as String?,
      );

  final String uid;
  final String name;

  /// The AP's SSID, when known — used to auto-join on switch.
  final String? ssid;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        if (ssid != null) 'ssid': ssid,
      };
}

final masterRegistryProvider =
    AsyncNotifierProvider<MasterRegistryNotifier, List<SavedMaster>>(
  MasterRegistryNotifier.new,
);

class MasterRegistryNotifier extends AsyncNotifier<List<SavedMaster>> {
  static const _key = 'masters';
  static const _lastUsedKey = 'masters.lastUsed';

  @override
  Future<List<SavedMaster>> build() => _load();

  Future<List<SavedMaster>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) SavedMaster.fromJson(e),
    ];
  }

  Future<void> _persist(List<SavedMaster> masters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final m in masters) m.toJson()]),
    );
    state = AsyncValue.data(masters);
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
