import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/session_gate.dart';
import '../features/dashboard/presentation/reorder_masters_screen.dart';
import '../features/extensions/presentation/extensions_screen.dart';
import '../features/firmware/presentation/firmware_screen.dart';
import '../features/mesh/presentation/mesh_screen.dart';
import '../features/onboarding/presentation/add_master_screen.dart';
import '../features/recovery/presentation/recovery_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/switches/presentation/reorder_screen.dart';

/// Route paths, one constant per screen. Feature blocks add theirs here
/// so deep links stay discoverable in one place.
abstract final class Routes {
  static const home = '/';
  static const reorder = '/switches/reorder';
  static const reorderMasters = '/masters/reorder';
  static const recovery = '/recovery';
  static const addMaster = '/add-master';
  static const extensions = '/extensions';
  static const mesh = '/mesh';
  static const firmware = '/firmware';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const SessionGate(),
      ),
      GoRoute(
        path: Routes.reorder,
        builder: (context, state) => const ReorderScreen(),
      ),
      GoRoute(
        path: Routes.reorderMasters,
        builder: (context, state) => const ReorderMastersScreen(),
      ),
      GoRoute(
        path: Routes.recovery,
        builder: (context, state) => const RecoveryScreen(),
      ),
      GoRoute(
        path: Routes.addMaster,
        builder: (context, state) => const AddMasterScreen(),
      ),
      GoRoute(
        path: Routes.extensions,
        builder: (context, state) => const ExtensionsScreen(),
      ),
      GoRoute(
        path: Routes.mesh,
        builder: (context, state) => const MeshScreen(),
      ),
      GoRoute(
        path: Routes.firmware,
        builder: (context, state) => const FirmwareScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
