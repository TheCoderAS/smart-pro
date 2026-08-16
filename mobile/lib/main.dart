import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/l10n/app_localizations.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/permissions/startup_gate.dart';
import 'core/transport/transport_coordinator.dart';
import 'features/settings/application/theme_mode.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Connect as soon as the isolate starts, rather than waiting for the
  // dashboard's first frame.
  //
  // On Android the engine is kept warm in the background, so this isolate
  // can be running with no window and no frames at all — and the whole
  // point of keeping it warm is that the link is already up when the user
  // opens the app. Hanging the first connect off a post-frame callback
  // made it wait for a frame that may never come.
  unawaited(container.read(transportCoordinatorProvider).reconcile());
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const UnisyncApp(),
    ),
  );
}

class UnisyncApp extends ConsumerWidget {
  const UnisyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Every screen sits behind the readiness pass: permissions asked
      // upfront on load, radios prompted on when they are off.
      builder: (context, child) =>
          StartupGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
