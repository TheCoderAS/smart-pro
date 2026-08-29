import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/transport/access_reset.dart';

/// The false "your access was reset" screen: during reconnect churn a
/// single proof can fail purely on timing, and one blip used to throw
/// the full sign-out screen at a user whose password never changed. A
/// real password change rejects again on the very next reconnect, so
/// two strikes inside the window is the honest test.
void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('one rejected proof is noise, two inside the window are real', () {
    final c = makeContainer();
    final n = c.read(accessResetProvider.notifier);

    n.strike();
    expect(c.read(accessResetProvider), isFalse,
        reason: 'a single blip must not sign out');

    n.strike();
    expect(c.read(accessResetProvider), isTrue,
        reason: 'a repeat is a changed password');
  });

  test('clear() resets both the flag and the pending strike', () {
    final c = makeContainer();
    final n = c.read(accessResetProvider.notifier);

    n.strike();
    n.clear();
    n.strike();
    expect(c.read(accessResetProvider), isFalse,
        reason: 'a cleared strike must not pair with a later one');
  });
}
