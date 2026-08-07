import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/session_gate.dart';
import '../features/onboarding/presentation/add_master_screen.dart';
import '../features/recovery/presentation/recovery_screen.dart';
import '../features/switches/presentation/reorder_screen.dart';

/// Route paths, one constant per screen. Feature blocks add theirs here
/// so deep links stay discoverable in one place.
abstract final class Routes {
  static const home = '/';
  static const reorder = '/switches/reorder';
  static const recovery = '/recovery';
  static const addMaster = '/add-master';
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
        path: Routes.recovery,
        builder: (context, state) => const RecoveryScreen(),
      ),
      GoRoute(
        path: Routes.addMaster,
        builder: (context, state) => const AddMasterScreen(),
      ),
    ],
  );
});
