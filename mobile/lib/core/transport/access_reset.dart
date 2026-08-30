import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/mesh/application/mesh_join_mode.dart';

/// Set when a master rejects our session over BLE (the password was
/// changed, so every token everywhere died — v5.1 Epic 5).
///
/// BLE has no login, so the app must not show a login form: the gate
/// renders an instruction screen telling the user which Wi-Fi network to
/// join to sign in again. Cleared once a fresh Wi-Fi login succeeds.
final accessResetProvider =
    NotifierProvider<AccessResetNotifier, bool>(AccessResetNotifier.new);

class AccessResetNotifier extends Notifier<bool> {
  /// Two rejected proofs inside this window mean the password really
  /// changed; one alone is noise. During reconnect churn (a roam, the
  /// two-master case) a single handshake can fail purely on timing —
  /// interleaved connections desync the per-connection nonce — and that
  /// one blip used to throw the "your access was reset" screen at a user
  /// whose password had not changed at all.
  static const window = Duration(seconds: 90);

  DateTime? _firstStrike;

  @override
  bool build() => false;

  /// A master rejected our proof. The first strike arms; a second within
  /// [window] confirms — a genuinely changed password rejects again on
  /// the very next reconnect, within seconds.
  void strike() {
    // A rejection from a master that never issued our token proves
    // nothing about our password. While the app is parked on another
    // master's network for a mesh invite, every 401 is expected.
    if (ref.read(meshJoinModeProvider)) return;
    final now = DateTime.now();
    final first = _firstStrike;
    if (first != null && now.difference(first) <= window) {
      _firstStrike = null;
      if (!state) state = true;
      return;
    }
    _firstStrike = now;
  }

  void clear() {
    _firstStrike = null;
    if (state) state = false;
  }
}
