import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the user is deliberately parked on ANOTHER master's
/// network to hand it an invite.
///
/// For those couple of minutes almost every assumption the app runs on
/// is false on purpose: the device answering on 192.168.4.1 is not the
/// home, our token means nothing to it, and the home's network is out of
/// reach. Left to itself the app would fight the user — the session
/// bootstrap would see a stranger's uid and throw up "a different switch
/// answered", the heartbeat would count misses against a master it
/// cannot reach, and two 401s from a device that never issued our token
/// would trip the "your access was reset" screen in the middle of a
/// perfectly healthy join.
///
/// So the machinery stands down for the duration. Nothing here changes
/// what the app does the rest of the time: this is false in every
/// standalone home, always.
final meshJoinModeProvider =
    NotifierProvider<MeshJoinModeNotifier, bool>(MeshJoinModeNotifier.new);

class MeshJoinModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() {
    if (!state) state = true;
  }

  void leave() {
    if (state) state = false;
  }
}
