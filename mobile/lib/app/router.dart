import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/session_gate.dart';
import '../features/switches/presentation/reorder_screen.dart';

/// Route paths, one constant per screen. Feature blocks add theirs here
/// so deep links stay discoverable in one place.
abstract final class Routes {
  static const home = '/';
  static const reorder = '/switches/reorder';
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
    ],
  );
});
