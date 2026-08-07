import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route paths, one constant per screen. Feature blocks add theirs here
/// so deep links stay discoverable in one place.
abstract final class Routes {
  static const home = '/';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const _BootstrapHomeScreen(),
      ),
    ],
  );
});

/// Placeholder home until the auth gate (block 5) and dashboard
/// (block 7) land. Proves theme + routing + Riverpod wiring.
class _BootstrapHomeScreen extends StatelessWidget {
  const _BootstrapHomeScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Unisync')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.toggle_on_outlined, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Unisync',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The wall should be smarter than the bulb.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
