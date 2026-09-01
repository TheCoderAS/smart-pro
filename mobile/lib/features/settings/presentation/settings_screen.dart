import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/router.dart';
import '../../../core/api/failure.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/transport/ble_session.dart' show MeshActionFailed;
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/stay_alive.dart';
import '../../../core/transport/transport_coordinator.dart';
import '../../../core/transport/transport_manager.dart';
import '../../../core/widgets/connection_bar.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/transport_refusal.dart';
import '../../../core/widgets/wifi_guard.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../../core/ws/state_socket.dart';
import '../../auth/application/session.dart';
import '../../auth/data/auth_repository.dart';
import '../application/theme_mode.dart';

/// The real installed version, read from the platform (never hardcoded —
/// a hardcoded string drifted from the release the moment it shipped).
///
/// Display version only. The build number is CI's bookkeeping: it names
/// a run, not the app someone is holding.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'Version ${info.version}';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final transportPref = ref.watch(transportPreferenceProvider);
    final session = ref.watch(sessionProvider).value;
    final info = switch (session) {
      Authenticated(:final info) => info,
      _ => null,
    };
    final masters = ref.watch(masterRegistryProvider).value ?? const [];
    final home = masters.isEmpty ? null : masters.first;
    // The mesh identity comes from the registry, not a live request: it
    // was learned from the master over Wi-Fi and cached, so this screen
    // names the home correctly over Bluetooth too — and never puts an
    // HTTP request on a link that is deliberately Bluetooth-only.
    final meshName = (home?.inMesh ?? false) ? home!.meshName : null;
    final masterName = ref.watch(stateSocketProvider).value?.masterName ??
        (home != null ? home.name : 'this switch');
    // In a mesh, this phone is set up with the whole home, not one box —
    // so that is what it disconnects from.
    final disconnectName = meshName ?? masterName;
    final version = ref.watch(appVersionProvider).value ?? 'Version —';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: const ConnectionBar(),
      ),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (mode) {
              if (mode != null) {
                ref.read(themeModeProvider.notifier).set(mode);
              }
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('Follow system'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('Dark'),
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Connection'),
          RadioGroup<TransportPreference>(
            groupValue: transportPref,
            onChanged: (pref) async {
              if (pref == null) return;
              final messenger = ScaffoldMessenger.of(context);
              final l10n = AppLocalizations.of(context)!;
              final result =
                  await ref.read(transportCoordinatorProvider).choose(pref);
              showTransportRefusal(messenger, l10n, result);
            },
            child: const Column(
              children: [
                RadioListTile<TransportPreference>(
                  value: TransportPreference.wifi,
                  title: Text('Wi-Fi'),
                  subtitle: Text("Over the switch's own network."),
                ),
                RadioListTile<TransportPreference>(
                  value: TransportPreference.bluetooth,
                  title: Text('Bluetooth'),
                  subtitle: Text(
                    'Your phone keeps its own network. While earphones '
                    'stream audio, taps can lag — Wi-Fi is quicker then.',
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          _SectionHeader(meshName != null ? 'This home' : 'This switch'),
          // No uid/firmware tile: in a mesh it named whichever box the
          // radio happened to hold, under a header about the whole home,
          // and the running version is one tap away under Firmware update.
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text(
              meshName != null ? 'Rename this mesh' : 'Rename this master',
            ),
            subtitle: const Text('The name at the top of the home screen.'),
            // In a mesh that name IS the mesh's, so renaming the master
            // changed nothing a person could see. Both work on either
            // transport (firmware 11.32.0 for the mesh).
            onTap: meshName != null
                ? () => _renameMesh(context, ref, meshName)
                : (info == null ? null : () => _renameMaster(context, ref)),
            enabled: meshName != null || info != null,
          ),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Mesh'),
            subtitle: Text(
              meshName != null
                  ? 'In "$meshName" — masters, invites and peers.'
                  : 'Not in a mesh. Link switches into one home.',
            ),
            trailing: const Icon(Icons.chevron_right),
            // Not gated on Wi-Fi any more. Leaving a mesh and removing a
            // master from it are the two ways out of a home, and needing
            // Wi-Fi for them made Bluetooth a mode you could drive a mesh
            // from and never undo. Creating, inviting and joining still
            // ask for Wi-Fi on the screen itself — they rebuild the AP.
            onTap: () => unawaited(context.push(Routes.mesh)),
          ),
          // No "Reorder masters" screen: the card order is a long-press
          // and drag on the home screen, and two ways to do one thing is
          // one more than the screen needs.
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Firmware update'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(context.push(Routes.firmware)),
          ),
          const Divider(),
          const _SectionHeader('Security'),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Reset access'),
            subtitle: const Text(
              'Set a new password. Everyone with the old one is signed out.',
            ),
            enabled: info != null,
            onTap: () => _changePassword(context, ref),
          ),
          const Divider(),
          const _SectionHeader('Reliability'),
          const _StayAliveTile(),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.link_off,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Disconnect $disconnectName',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: Text(
              meshName != null
                  ? 'Erase this home from the phone and start over.'
                  : 'Erase everything from this phone and start over.',
            ),
            // Always tappable — no dead ends, whatever state the
            // connection is in.
            onTap: () =>
                _disconnect(context, ref, disconnectName, meshed: meshName != null),
          ),
          const Divider(),
          const _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.phone_iphone),
            title: const Text('Unisync'),
            subtitle: Text(version),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    // Changing the password is a Wi-Fi-only flow (BLE spec v2 §9).
    if (!requireWifi(context, ref)) return;
    final currentController = TextEditingController();
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset access'),
        content: StatefulBuilder(
          builder: (context, setState) {
            final fresh = controller.text;
            final canSave = currentController.text.isNotEmpty &&
                fresh.length >= 8 &&
                fresh == confirmController.text;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PasswordField(
                  controller: currentController,
                  label: 'Current password',
                ),
                PasswordField(
                  controller: controller,
                  label: 'New password',
                  helper: 'At least 8 characters. Every signed-in device '
                      'must sign in again.',
                  helperMaxLines: 3,
                ),
                PasswordField(
                  controller: confirmController,
                  label: 'Repeat password',
                ),
                const SizedBox(height: 16),
                FormActions(
                  saveLabel: 'Change',
                  canSave: canSave,
                  onCancel: () => Navigator.of(dialogContext).pop(false),
                  onSave: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        ),
      ),
    );
    final fresh = controller.text;
    final current = currentController.text;
    currentController.dispose();
    controller.dispose();
    confirmController.dispose();
    if (!(ok ?? false)) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    // Prove the current password before changing it. /api/password is
    // token-authenticated and takes no `old`, so the check is a login
    // with what the user typed -- the one endpoint that verifies a
    // password against the credential actually in force (which in a mesh
    // is the mesh's, not this box's).
    //
    // The cost is bounded and worth naming: five wrong entries lock
    // *new* sign-ins for five minutes (AUTH_MAX_FAILS / AUTH_LOCKOUT_MS).
    // It cannot strand anyone -- auth_valid() reads the token and never
    // consults that lock, so this session keeps working -- and a correct
    // entry resets the counter to zero before anything is changed.
    try {
      await ref.read(authRepositoryProvider).changePasswordVerified(
            current: current,
            fresh: fresh,
          );
    } on ApiFailure catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e) {
            // 401 here means one thing only, and "Not authorized (401)"
            // is not it.
            Unauthorized() => 'That is not the current password.',
            _ => e.describe(),
          }),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Password changed. Reconnecting…')),
    );
    final wifi = ref.read(wifiServiceProvider);
    final ssid = await wifi.currentSsid();
    if (ssid != null) {
      // ignore: unawaited_futures
      wifi.join(ssid, fresh);
    }
    await ref.read(sessionProvider.notifier).handlePasswordChanged(fresh);
  }

  /// Renames the MESH, which is what the home screen actually shows once
  /// masters are linked. Works on either transport: over Wi-Fi through
  /// /api/mesh/rename, over Bluetooth through the mesh_rename verb added
  /// in firmware 11.32.0.
  ///
  /// Every member follows the rename and changes SSID together, so over
  /// Wi-Fi the phone's own network disappears mid-flight — the copy says
  /// so rather than letting it look like a failure.
  Future<void> _renameMesh(
    BuildContext context,
    WidgetRef ref,
    String? currentName,
  ) async {
    final overWifi =
        ref.read(currentTransportProvider) == TransportKind.wifi;
    final controller = TextEditingController(text: currentName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename this mesh'),
        content: StatefulBuilder(
          builder: (context, setState) {
            final value = controller.text.trim();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 31,
                  decoration: const InputDecoration(labelText: 'Mesh name'),
                  onChanged: (_) => setState(() {}),
                ),
                if (overWifi)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Every switch changes network name together, so this '
                      'phone will drop off and rejoin under the new one.',
                    ),
                  ),
                const SizedBox(height: 8),
                FormActions(
                  canSave: value.isNotEmpty && value != currentName,
                  onCancel: () => Navigator.of(dialogContext).pop(),
                  onSave: () => Navigator.of(dialogContext).pop(value),
                ),
              ],
            );
          },
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(activeControlProvider).renameMesh(name);
    } on Exception catch (e) {
      // The master's own words when it has them: over Bluetooth it says
      // why it refused, and paraphrasing that helps nobody.
      final msg = switch (e) {
        ApiFailure() => e.describe(),
        MeshActionFailed() => e.reason,
        _ => "Couldn't rename — check the connection.",
      };
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    // Cached so every screen names the home right, on either transport
    // and offline — the same reason the mesh id is cached.
    final home = ref.read(masterRegistryProvider).value?.firstOrNull;
    if (home != null && home.inMesh) {
      await ref.read(masterRegistryProvider.notifier).setMesh(
            uid: home.uid,
            inMesh: true,
            meshId: home.meshId!,
            meshName: name,
          );
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          overWifi
              ? 'Renamed to "$name". Rejoin the new network when it appears.'
              : 'Renamed to "$name".',
        ),
      ),
    );
  }

  Future<void> _renameMaster(BuildContext context, WidgetRef ref) async {
    // Rename works on either transport (firmware v11.18.0).
    final current = switch (ref.read(sessionProvider).value) {
      Authenticated(:final info) => info,
      _ => null,
    };
    final controller = TextEditingController(
      text: ref.read(stateSocketProvider).value?.masterName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename'),
        content: StatefulBuilder(
          builder: (context, setState) {
            final value = controller.text.trim();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                FormActions(
                  canSave: value.isNotEmpty,
                  onCancel: () => Navigator.of(dialogContext).pop(),
                  onSave: () => Navigator.of(dialogContext).pop(value),
                ),
              ],
            );
          },
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || current == null) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(activeControlProvider).renameMaster(name);
      messenger.showSnackBar(const SnackBar(content: Text('Renamed.')));
    } on Exception catch (e) {
      final msg = e is ApiFailure
          ? e.describe()
          : "Couldn't rename — check the connection.";
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// "Disconnect `<name>`": full wipe, then the welcome screen — the app
  /// forgets this switch ever existed, exactly like a fresh install.
  Future<void> _disconnect(
    BuildContext context,
    WidgetRef ref,
    String disconnectName, {
    required bool meshed,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Disconnect $disconnectName?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Everything saved on this phone is erased — sign-in, names '
              'and settings — and the app starts over like a new install. '
              '${meshed ? "Every master in the mesh keeps working, and the "
                  "mesh itself is untouched." : "The switch itself keeps "
                  "working."}',
            ),
            const SizedBox(height: 16),
            FormActions(
              saveLabel: 'Disconnect',
              destructive: true,
              onCancel: () => Navigator.of(dialogContext).pop(false),
              onSave: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (!(confirmed ?? false)) return;
    // Best-effort server-side sign-out, fired without waiting: on an
    // unreachable master this request can sit out a 5 s timeout, and
    // the wipe is app-side work that must feel instant.
    unawaited(ref.read(authRepositoryProvider).logout());
    await ref.read(sessionProvider.notifier).disconnectAndWipe();
    // The theme preference was just erased with everything else; drop
    // the in-memory copy too so even the look resets to day one.
    ref.invalidate(themeModeProvider);
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// Android only. iOS suspends apps and terminates them when swiped away,
/// so there is nothing to offer there and pretending otherwise would be
/// worse than the tile's absence.
class _StayAliveTile extends ConsumerStatefulWidget {
  const _StayAliveTile();

  @override
  ConsumerState<_StayAliveTile> createState() => _StayAliveTileState();
}

class _StayAliveTileState extends ConsumerState<_StayAliveTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    ref.read(stayAliveProvider).isEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.bolt_outlined),
          value: on,
          title: const Text('Keep switches ready'),
          subtitle: const Text(
            'Stay running in the background so taps fire instantly. '
            'Shows a permanent notification.',
          ),
          onChanged: (v) async {
            setState(() => _on = v);
            await ref.read(stayAliveProvider).setEnabled(v);
          },
        ),
        if (on)
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('Not staying connected?'),
            subtitle: const Text(
              "Allow Unisync to run in the background in your phone's "
              'battery settings.',
            ),
            onTap: () => ref.read(stayAliveProvider).openBatterySettings(),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
