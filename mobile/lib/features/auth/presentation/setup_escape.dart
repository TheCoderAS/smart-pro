import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/master_registry.dart';
import '../application/session.dart';

/// The universal escape hatch, by decree: NO screen in this app may be a
/// dead end. Every identity/setup screen offers this — forget the current
/// setup (with consent) and land on the setup screen.
Future<void> confirmSetupDifferentSwitch(
  BuildContext context,
  WidgetRef ref,
) async {
  final masters = ref.read(masterRegistryProvider).value ?? const [];
  final name = masters.isEmpty ? 'this switch' : '"${masters.first.name}"';
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Set up a different switch?'),
      content: Text(
        'This removes $name from the app, including its saved sign-in. '
        'The switch itself is not changed, and you can add it back any '
        'time with its network name and password.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove and set up new'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(sessionProvider.notifier).forgetHome();
}

/// The escape as a ready-made button, so adding it to a screen is one
/// line and every screen words it identically.
class SetupEscapeButton extends ConsumerWidget {
  const SetupEscapeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => confirmSetupDifferentSwitch(context, ref),
      icon: const Icon(Icons.swap_horiz),
      label: const Text('Set up a different switch'),
    );
  }
}
