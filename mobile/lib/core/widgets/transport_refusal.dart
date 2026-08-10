import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/l10n/app_localizations.dart';
import '../transport/transport_coordinator.dart';

/// Explains a refused transport change (Epic 5: "A denied permission
/// leaves the user in their current mode with a clear explanation and a
/// path to settings — never a half-switched state or a silent failure").
///
/// Takes the messenger rather than a BuildContext so callers can capture
/// it before the sheet/dialog they were in is popped.
void showTransportRefusal(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  TransportChoice result,
) {
  switch (result) {
    case TransportChoice.ok:
      return;
    case TransportChoice.needsWifiLogin:
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.btNeedsWifiLogin)),
      );
    case TransportChoice.permissionDenied:
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.btPermissionDenied),
          action: SnackBarAction(
            label: l10n.openSettings,
            onPressed: openAppSettings,
          ),
        ),
      );
  }
}
