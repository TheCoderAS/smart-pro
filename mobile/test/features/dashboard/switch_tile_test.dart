import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unisync/app/l10n/app_localizations.dart';
import 'package:unisync/core/ws/state_dto.dart';
import 'package:unisync/features/dashboard/application/switch_overrides.dart';
import 'package:unisync/features/dashboard/presentation/dashboard_screen.dart';
import 'package:unisync/features/switches/data/switch_repository.dart';

class MockSwitchRepository extends Mock implements SwitchRepository {}

void main() {
  late MockSwitchRepository repo;

  setUp(() {
    repo = MockSwitchRepository();
  });

  Widget wrap(Widget child, ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [switchRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  const sw = SwitchState(id: 'ext0_1', name: 'Fan', ch: 1);

  testWidgets('tap toggles optimistically before the POST resolves',
      (tester) async {
    when(() => repo.setRelay(id: 'ext0_1', on: true, ch: 1))
        .thenAnswer((_) async {});
    final c = makeContainer();

    await tester.pumpWidget(wrap(const SwitchTile(sw: sw), c));
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    // Optimistic: shows On even though no snapshot arrived.
    expect(find.text('On'), findsOneWidget);
    verify(() => repo.setRelay(id: 'ext0_1', on: true, ch: 1)).called(1);

    // Drain the optimistic safety timeout so no timer leaks into teardown.
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('failed POST rolls the tile back', (tester) async {
    when(() => repo.setRelay(id: 'ext0_1', on: true, ch: 1))
        .thenThrow(Exception('unreachable'));
    final c = makeContainer();

    await tester.pumpWidget(wrap(const SwitchTile(sw: sw), c));
    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('Off'), findsOneWidget);
    expect(c.read(switchOverridesProvider), isEmpty);
  });

  testWidgets('offline switch is not tappable', (tester) async {
    const offline = SwitchState(id: 'ext0_2', name: 'Lamp', online: false);
    final c = makeContainer();

    await tester.pumpWidget(wrap(const SwitchTile(sw: offline), c));
    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('Offline'), findsOneWidget);
    verifyNever(
      () => repo.setRelay(
        id: any(named: 'id'),
        on: any(named: 'on'),
        ch: any(named: 'ch'),
      ),
    );
  });
}
