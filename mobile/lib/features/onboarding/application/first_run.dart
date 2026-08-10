import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three one-time moments of first-time setup (story Epic 1).
///
/// Each is asked **once** and then never again: the welcome screen on a
/// fresh install, the optional "change your password?" prompt on the first
/// dashboard, and the Wi-Fi/Bluetooth preference. The story is explicit that
/// the transport question must never reappear on launch, so the answers live
/// in preferences rather than in memory.
class FirstRunFlags {
  const FirstRunFlags({
    required this.welcomeSeen,
    required this.passwordPromptSeen,
    required this.transportAsked,
  });

  /// Nothing has been read yet — callers should wait rather than assume a
  /// fresh install and flash the welcome screen at a returning user.
  const FirstRunFlags.unknown()
      : welcomeSeen = true,
        passwordPromptSeen = true,
        transportAsked = true;

  final bool welcomeSeen;
  final bool passwordPromptSeen;
  final bool transportAsked;
}

final firstRunProvider =
    AsyncNotifierProvider<FirstRunNotifier, FirstRunFlags>(
  FirstRunNotifier.new,
);

class FirstRunNotifier extends AsyncNotifier<FirstRunFlags> {
  static const _welcome = 'firstrun.welcome';
  static const _password = 'firstrun.passwordPrompt';
  static const _transport = 'firstrun.transportAsked';

  @override
  Future<FirstRunFlags> build() async {
    final prefs = await SharedPreferences.getInstance();
    return FirstRunFlags(
      welcomeSeen: prefs.getBool(_welcome) ?? false,
      passwordPromptSeen: prefs.getBool(_password) ?? false,
      transportAsked: prefs.getBool(_transport) ?? false,
    );
  }

  Future<void> _mark(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    ref.invalidateSelf();
    await future;
  }

  Future<void> markWelcomeSeen() => _mark(_welcome);
  Future<void> markPasswordPromptSeen() => _mark(_password);
  Future<void> markTransportAsked() => _mark(_transport);
}
