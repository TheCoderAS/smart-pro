import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transport/link_state.dart';

/// The persistent connection indicator (story Epic 1: "the user always
/// knows the connection state without doing anything").
///
/// It sits under the app bar of every screen that can act on the master, not
/// just the dashboard — discovering a dead link by tapping something on the
/// extensions screen is the same bug as discovering it on the dashboard.
/// Silent while connected, because a permanent green bar is noise.
class ConnectionBar extends ConsumerWidget implements PreferredSizeWidget {
  const ConnectionBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(28);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(linkStateProvider);
    if (link.connected) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final (icon, text, colour) = switch (link) {
      LinkState.outOfRange => (
          Icons.wifi_off_rounded,
          'Out of range — showing the last state we saw',
          scheme.error,
        ),
      _ => (
          Icons.sync_rounded,
          'Reconnecting…',
          scheme.tertiary,
        ),
    };

    return Material(
      color: colour.withValues(alpha: 0.12),
      child: SizedBox(
        height: 28,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: colour),
            const SizedBox(width: 8),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colour,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
