import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';
import 'package:unisync/main.dart';

/// Boot smoke test. The default (un-mocked) session hits an
/// unreachable master, so the app must land on the "can't reach your
/// switch" screen rather than crashing or spinning forever.
class _UnreachableRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const Unreachable();
}

void main() {
  testWidgets('app boots to the unreachable screen without a device',
      (tester) async {
    // No paired master / no transport preference — the BLE cold-start
    // path stays dormant and the app lands on the unreachable screen.
    // Past the welcome screen: a fresh install lands there instead, which
    // has its own coverage in session_test.dart.
    SharedPreferences.setMockInitialValues({'firstrun.welcome': true});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_UnreachableRepo()),
        ],
        child: const UnisyncApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('reach your switch'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
