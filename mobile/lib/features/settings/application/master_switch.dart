import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/logging/log.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../auth/data/auth_repository.dart';

/// How a switch to another master ended.
///
/// The point of having more than one outcome is that "connect to B's
/// network" is an instruction a user can act on and "B is out of range" is
/// not — the story insists those are different screens, and that a login
/// prompt only ever appears for an actual rejected login.
sealed class SwitchOutcome {
  const SwitchOutcome();
}

/// The target answered with its own uid. The session check runs next.
final class SwitchArrived extends SwitchOutcome {
  const SwitchArrived();
}

/// Something answered, but it was a different master — the phone is on
/// somebody else's network.
final class SwitchWrongNetwork extends SwitchOutcome {
  const SwitchWrongNetwork({required this.target, this.foundName});

  final SavedMaster target;

  /// The master that did answer, named if we know it.
  final String? foundName;
}

/// Nothing answered.
final class SwitchUnreachable extends SwitchOutcome {
  const SwitchUnreachable(this.target);
  final SavedMaster target;
}

final masterSwitchProvider =
    Provider<MasterSwitchService>(MasterSwitchService.new);

/// Moves the app from one master to another.
///
/// Identity is proven by probing the info endpoint and comparing the uid —
/// never by reading the phone's network name. That is what lets the app
/// tell "wrong network" from "out of range" without any OS network-name
/// access, and therefore without asking for location permission.
class MasterSwitchService {
  MasterSwitchService(this._ref);

  final Ref _ref;

  Future<SwitchOutcome> switchTo(SavedMaster target) async {
    final wifi = _ref.read(wifiServiceProvider);
    final ssid = target.ssid;

    // Join the target's network first when we know how. In a mesh every
    // master serves the same SSID, so this is a no-op there.
    if (ssid != null && ssid.isNotEmpty) {
      final password =
          await _ref.read(secureStoreProvider).readPassword(target.uid);
      if (password != null) {
        await wifi.join(ssid, password);
      }
    }

    // The probe is the identity check.
    try {
      final info = await _ref.read(authRepositoryProvider).info();
      if (info.uid == target.uid) {
        // Cache what the master says its network is called, so the next
        // instruction copy is right even after a rename.
        await _ref.read(masterRegistryProvider.notifier).ensure(
              uid: info.uid,
              ssid: info.ssid,
            );
        return const SwitchArrived();
      }
      return SwitchWrongNetwork(
        target: target,
        foundName: await _nameFor(info.uid) ?? info.ssid,
      );
    } on Unreachable {
      return SwitchUnreachable(target);
    } on ApiFailure catch (e) {
      log.w('master switch probe failed: ${e.describe()}');
      return SwitchUnreachable(target);
    }
  }

  Future<String?> _nameFor(String uid) async {
    final masters = _ref.read(masterRegistryProvider).value ?? const [];
    for (final m in masters) {
      if (m.uid == uid) return m.name;
    }
    return null;
  }
}
