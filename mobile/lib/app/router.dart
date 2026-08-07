import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

/// Route paths, kept as constants so features can reference them without
/// stringly-typed duplication as screens land (PLAN.md §7).
abstract final class AppRoutes {
  static const home = '/';
}

@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _PlaceholderHomeScreen(),
      ),
    ],
  );
}

/// Stand-in for the dashboard until the auth + state-socket blocks land.
class _PlaceholderHomeScreen extends StatelessWidget {
  const _PlaceholderHomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unisync')),
      body: const Center(
        child: Text('Unisync app bootstrap — features land per mobile/PLAN.md'),
      ),
    );
  }
}
