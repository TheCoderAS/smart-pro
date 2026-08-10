import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../transport/control_transport.dart';
import '../transport/transport_coordinator.dart';
import '../transport/transport_manager.dart';

/// Returns true when the active transport can carry a Wi-Fi-only action
/// (firmware transfer, mesh admin, password change, rename/assign — BLE
/// spec v2 §9). Over BLE it shows a sheet steering the user to Wi-Fi and
/// returns false, so callers do: `if (!requireWifi(context, ref)) return;`
bool requireWifi(BuildContext context, WidgetRef ref) {
  if (ref.read(currentTransportProvider) != TransportKind.ble) return true;
  showWifiNeededSheet(context, ref);
  return false;
}

void showWifiNeededSheet(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.wifiOnlyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.wifiOnlyBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  ref
                      .read(transportCoordinatorProvider)
                      .choose(TransportPreference.wifi);
                },
                icon: const Icon(Icons.wifi_rounded),
                label: Text(l10n.joinWifi),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
