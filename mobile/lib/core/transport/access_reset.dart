import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set when a master rejects our session over BLE (the password was
/// changed, so every token everywhere died — v5.1 Epic 5).
///
/// BLE has no login, so the app must not show a login form: the gate
/// renders an instruction screen telling the user which Wi-Fi network to
/// join to sign in again. Cleared once a fresh Wi-Fi login succeeds.
final accessResetProvider =
    NotifierProvider<AccessResetNotifier, bool>(AccessResetNotifier.new);

class AccessResetNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void flag() {
    if (!state) state = true;
  }

  void clear() {
    if (state) state = false;
  }
}
