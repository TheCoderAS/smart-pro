import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/main.dart';

void main() {
  testWidgets('app boots to the home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: UnisyncApp()));
    await tester.pumpAndSettle();

    expect(find.text('Unisync'), findsWidgets);
    expect(
      find.text('The wall should be smarter than the bulb.'),
      findsOneWidget,
    );
  });
}
