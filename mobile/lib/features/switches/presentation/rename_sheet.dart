import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/transport/transport_manager.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/ws/state_dto.dart';

/// Long-press affordance on a switch tile: rename, and the power-cut
/// policy that the story puts in this same menu. Both land as authenticated
/// mutations; the next snapshot repaints every consumer.
/// [masterUid] names the master that owns this switch — null for the one
/// the app is connected to. Without it every rename and policy change
/// landed on whichever master held the link, so renaming a switch from a
/// peer's card quietly renamed a switch on the connected master instead.
Future<void> showRenameSwitchSheet(
  BuildContext context,
  WidgetRef ref,
  SwitchState sw, {
  String? masterUid,
}) {
  final controller = TextEditingController(text: sw.name);
  var restore = sw.restore;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
      ),
      child: StatefulBuilder(
        builder: (context, setState) {
          final name = controller.text.trim();
          final renamed = name.isNotEmpty && name != sw.name;
          final policyChanged = restore != sw.restore;
          final canSave = renamed || policyChanged;
          Future<void> save() async {
            final messenger = ScaffoldMessenger.of(context);
            final control = ref.read(activeControlProvider);
            Navigator.of(sheetContext).pop();
            try {
              if (renamed) {
                await control.renameSwitch(
                  id: sw.id,
                  name: name,
                  masterUid: masterUid,
                );
              }
              if (policyChanged) {
                await control.setRestore(
                  id: sw.id,
                  restore: restore,
                  masterUid: masterUid,
                );
              }
            } on Exception {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text("Couldn't save — check the connection."),
                ),
              );
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Switch settings',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (canSave) save();
                },
              ),
              const SizedBox(height: 8),
              // Default is "always start off": nothing energizes after an
              // outage unless this switch was opted in. Restoring can only
              // ever turn a switch on, never off.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: restore,
                onChanged: (v) => setState(() => restore = v),
                title: const Text('Restore after a power cut'),
                subtitle: Text(
                  restore
                      ? 'Comes back on if it was on when the power went.'
                      : 'Always starts off. Nothing turns on by itself.',
                ),
                isThreeLine: false,
              ),
              const SizedBox(height: 8),
              FormActions(
                canSave: canSave,
                onCancel: () => Navigator.of(sheetContext).pop(),
                onSave: save,
              ),
            ],
          );
        },
      ),
    ),
  ).whenComplete(controller.dispose);
}
