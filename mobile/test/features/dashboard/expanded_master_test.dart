import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/features/dashboard/application/master_cards.dart';

/// "One card is always open" was a courtesy that had hardened into a
/// rule: the dashboard re-applied it on every rebuild, so closing the
/// last open card reopened it immediately and a user could never see
/// their whole home at a glance.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer make() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('the first card opens itself on arrival', () {
    final c = make();
    c.read(expandedMasterProvider.notifier).defaultTo('A');
    expect(c.read(expandedMasterProvider), 'A');
  });

  test('closing the open card leaves everything shut, and it stays shut', () {
    final c = make();
    final expanded = c.read(expandedMasterProvider.notifier);
    expanded.defaultTo('A');
    expanded.toggle('A');
    expect(c.read(expandedMasterProvider), isNull);

    // The rebuild that follows calls defaultTo again. It must not undo
    // what the user just did.
    expanded.defaultTo('A');
    expect(c.read(expandedMasterProvider), isNull);
  });

  test('collapseAll shuts everything and sticks', () {
    final c = make();
    final expanded = c.read(expandedMasterProvider.notifier);
    expanded.defaultTo('A');
    expanded.toggle('B');
    expect(c.read(expandedMasterProvider), 'B');

    // Starting a card drag collapses the lot.
    expanded.collapseAll();
    expect(c.read(expandedMasterProvider), isNull);
    expanded.defaultTo('A');
    expect(c.read(expandedMasterProvider), isNull);
  });

  test('opening another card still swaps which one is open', () {
    final c = make();
    final expanded = c.read(expandedMasterProvider.notifier);
    expanded.toggle('A');
    expanded.toggle('B');
    expect(c.read(expandedMasterProvider), 'B');
  });

  test('card order is this phone\'s own, and persists locally', () async {
    final c = make();
    await c.read(masterCardOrderProvider.notifier).set(['B', 'A']);
    expect(c.read(masterCardOrderProvider), ['B', 'A']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(MasterCardOrderNotifier.key), ['B', 'A']);
  });
}
