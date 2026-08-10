import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/wifi/wifi_service.dart';
import '../data/mesh_repository.dart';
import '../domain/mesh_models.dart';

/// Adds another master to this mesh, end to end.
///
/// The join PIN and the mesh master's identity are fetched over the
/// authenticated session and **held in memory only — never rendered, never
/// logged**. The previous flow printed both on screen and asked the user to
/// retype them on the other phone: eight-odd taps, a credential on display,
/// and the PIN typed into whatever happened to be listening.
///
/// What the user does instead: pick the new switch, type the password from
/// its card. The app carries the invite across.
Future<void> runAddToMeshFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(meshRepositoryProvider);
  final wifi = ref.read(wifiServiceProvider);

  // The network we came from, so we can put the phone back afterwards.
  final meshSsid = await wifi.currentSsid();

  // Fetched first: if this master can't issue an invite there is no point
  // walking the user through the rest.
  final MeshInvite invite;
  try {
    invite = await repo.invite();
  } on ApiFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.describe())));
    return;
  }
  if (!context.mounted) return;

  final target = await _pickNewMaster(context, ref);
  if (target == null || !context.mounted) return;

  messenger.showSnackBar(
    SnackBar(content: Text('Connecting to ${target.ssid}…')),
  );

  final joined = await wifi.join(target.ssid, target.password);
  if (!joined) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't join ${target.ssid}. Check the password on its card.",
        ),
      ),
    );
    return;
  }

  // The new master answers on the same address every master does.
  if (!await wifi.masterReachable()) {
    messenger.showSnackBar(
      SnackBar(content: Text('${target.ssid} did not answer. Try again.')),
    );
    if (meshSsid != null) await wifi.join(meshSsid, target.meshPassword);
    return;
  }

  try {
    // The credential goes straight from memory onto the wire.
    await repo.join(mac: invite.mac, pin: invite.pin);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${target.ssid} joined the mesh. It is restarting onto '
          '${meshSsid ?? "the mesh network"}.',
        ),
      ),
    );
  } on ApiFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.describe())));
  }

  // Put the phone back on the mesh network. The new master is restarting
  // onto it too, so this is where both end up.
  if (meshSsid != null) await wifi.join(meshSsid, target.meshPassword);
  await ref.read(meshStatusProvider.notifier).refresh();
}

class _Target {
  const _Target({
    required this.ssid,
    required this.password,
    required this.meshPassword,
  });

  final String ssid;

  /// The new master's factory password, from its card.
  final String password;

  /// This mesh's password, needed to get the phone back afterwards.
  final String meshPassword;
}

Future<_Target?> _pickNewMaster(BuildContext context, WidgetRef ref) async {
  final wifi = ref.read(wifiServiceProvider);
  List<String> nearby = const [];
  try {
    nearby = await wifi.scanSsids(ssidPrefix: 'Unisync');
  } on UnsupportedError {
    // iOS provides no third-party scanning — the user types the name.
  } on Object {
    // Permission refused or scanning unavailable; fall back to typing.
  }
  if (!context.mounted) return null;

  final ssidController = TextEditingController();
  final passController = TextEditingController();
  final meshPassController = TextEditingController();
  String? chosen = nearby.isNotEmpty ? nearby.first : null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add a switch to this mesh'),
      content: StatefulBuilder(
        builder: (context, setState) {
          final ssid = chosen ?? ssidController.text.trim();
          final canSave = ssid.isNotEmpty &&
              passController.text.length >= 8 &&
              meshPassController.text.length >= 8;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Power on the new switch and leave it where it will live. '
                  'The app does the rest.',
                ),
                const SizedBox(height: 16),
                if (nearby.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: chosen,
                    decoration:
                        const InputDecoration(labelText: 'New switch'),
                    items: [
                      for (final s in nearby)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => chosen = v),
                  )
                else
                  TextField(
                    controller: ssidController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'New switch network name',
                      helperText: 'Printed on the card in its box.',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                PasswordField(
                  controller: passController,
                  label: 'Its password',
                  helper: 'From the card in the new switch\'s box.',
                ),
                PasswordField(
                  controller: meshPassController,
                  label: 'This mesh\'s password',
                  helper: 'So the app can bring your phone back afterwards.',
                ),
                const SizedBox(height: 16),
                FormActions(
                  saveLabel: 'Add',
                  canSave: canSave,
                  onCancel: () => Navigator.of(dialogContext).pop(false),
                  onSave: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  final ssid = chosen ?? ssidController.text.trim();
  final pass = passController.text;
  final meshPass = meshPassController.text;
  ssidController.dispose();
  passController.dispose();
  meshPassController.dispose();
  if (!(ok ?? false) || ssid.isEmpty || pass.isEmpty) return null;
  return _Target(ssid: ssid, password: pass, meshPassword: meshPass);
}
