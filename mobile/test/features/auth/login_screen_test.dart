import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/features/auth/application/session.dart';
import 'package:unisync/features/auth/domain/models.dart';
import 'package:unisync/features/auth/presentation/login_screen.dart';

const _info = DeviceInfo(
  uptime: 1,
  freeHeap: 1,
  uid: 'C5F77720',
  fw: '11.13.2',
  auth: true,
);

void main() {
  Widget wrap(NeedsLogin state) {
    return ProviderScope(
      child: MaterialApp(home: LoginScreen(state: state)),
    );
  }

  testWidgets('shows master identity and password field', (tester) async {
    await tester.pumpWidget(wrap(const NeedsLogin(_info)));

    expect(find.textContaining('C5F77720'), findsOneWidget);
    expect(find.textContaining('11.13.2'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('401 failure shows wrong-password message', (tester) async {
    await tester.pumpWidget(
      wrap(const NeedsLogin(_info, failure: Unauthorized())),
    );

    expect(find.textContaining('Wrong password'), findsOneWidget);
  });

  testWidgets('423 lockout disables the form and shows countdown wording',
      (tester) async {
    await tester.pumpWidget(
      wrap(const NeedsLogin(_info, failure: LockedOut())),
    );

    expect(find.textContaining('Locked'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('429 shows back-off wording, form stays enabled',
      (tester) async {
    await tester.pumpWidget(
      wrap(const NeedsLogin(_info, failure: RateLimited())),
    );

    expect(find.textContaining('few seconds'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });
}
