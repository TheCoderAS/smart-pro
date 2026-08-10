import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/transport_coordinator.dart';
import '../application/first_run.dart';

/// The two questions the story asks once, on the first dashboard a user
/// ever reaches (Epic 1, steps 4 and 5).
///
/// Both are one-time by design. Keeping the factory password forever is an
/// accepted path — physical possession of the card is treated as physical
/// access to the home — so the password prompt is genuinely skippable and
/// never nags again. The transport question is asked "exactly once, at
/// setup — never again on launch".
Future<void> runFirstRunPrompts(BuildContext context, WidgetRef ref) async {
  final flags = await ref.read(firstRunProvider.future);

  if (!flags.passwordPromptSeen) {
    // Mark first: a user who dismisses this with the back gesture has still
    // been asked, and the story says asked once.
    await ref.read(firstRunProvider.notifier).markPasswordPromptSeen();
    if (!context.mounted) return;
    await _askChangePassword(context, ref);
  }

  if (!context.mounted) return;
  final after = await ref.read(firstRunProvider.future);
  if (!after.transportAsked) {
    await ref.read(firstRunProvider.notifier).markTransportAsked();
    if (!context.mounted) return;
    await _askTransport(context, ref);
  }
}

Future<void> _askChangePassword(BuildContext context, WidgetRef ref) async {
  final change = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Change your password?'),
      content: const Text(
        "You're signed in with the password from the card in the box. You "
        'can keep using it — the card is the key to your home, like a '
        'physical one.\n\n'
        'Changing it signs out every device, everywhere, and changes the '
        "Wi-Fi password too, so you'll rejoin the network.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep the card password'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Change it'),
        ),
      ],
    ),
  );
  if (change != true || !context.mounted) return;
  // Settings owns the change-password flow, including the rejoin dance.
  await context.push<void>(Routes.settings);
}

Future<void> _askTransport(BuildContext context, WidgetRef ref) async {
  final choice = await showDialog<TransportPreference>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('How should the app connect?'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "You're on your switch's Wi-Fi now. You can stay there, or "
            'control everything over Bluetooth and give your phone its own '
            'network back.',
          ),
          SizedBox(height: 12),
          Text(
            'You can change this any time in Settings.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(TransportPreference.bluetooth),
          child: const Text('Use Bluetooth'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(TransportPreference.wifi),
          child: const Text('Stay on Wi-Fi'),
        ),
      ],
    ),
  );
  if (choice == null) return;
  await ref.read(transportCoordinatorProvider).choose(choice);
}
