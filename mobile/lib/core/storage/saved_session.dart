import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../logging/log.dart';
import 'master_registry.dart';
import 'secure_store.dart';

/// A session issued over Wi-Fi and kept: the token, the master it belongs
/// to, and the mesh that master is part of.
typedef SavedSession = ({String uid, int? meshId, String token});

final savedSessionProvider =
    Provider<SavedSessionLoader>(SavedSessionLoader.new);

/// Reads the saved session out of the vault.
///
/// Exists because two callers need it independently and have to agree: the
/// auth bootstrap, which turns it into an `Authenticated` state, and the
/// transport coordinator, which needs a token in hand before Bluetooth can
/// come up at all.
///
/// Before this, the coordinator read only [tokenProvider] — empty on a cold
/// start until the bootstrap gets round to filling it — and treated "not
/// loaded yet" as "never signed in". The two are different answers and
/// callers act on them differently.
class SavedSessionLoader {
  SavedSessionLoader(this._ref);

  final Ref _ref;

  /// The best saved session: the last-used master if it has a token, else
  /// any paired master that does. Null when nothing is paired, or when no
  /// token was ever issued.
  Future<SavedSession?> read() async {
    final masters = await _ref.read(masterRegistryProvider.future);
    if (masters.isEmpty) return null;
    final store = _ref.read(secureStoreProvider);
    final lastUid = await _ref.read(masterRegistryProvider.notifier).lastUsed();
    final ordered = [
      ...masters.where((m) => m.uid == lastUid),
      ...masters.where((m) => m.uid != lastUid),
    ];
    for (final m in ordered) {
      final token = await store.readToken(m.uid);
      if (token != null) return (uid: m.uid, meshId: m.meshId, token: token);
    }
    return null;
  }

  /// The token in force, restoring it from the vault when the session
  /// bootstrap has not got there yet. Null only when there is genuinely
  /// no saved session.
  Future<String?> ensureToken() async {
    final live = _ref.read(tokenProvider);
    if (live != null) return live;
    try {
      final saved = await read();
      if (saved == null) return null;
      _ref.read(tokenProvider.notifier).set(saved.token);
      return saved.token;
    } on Object catch (e) {
      log.w('saved session read failed: $e');
      return null;
    }
  }
}
