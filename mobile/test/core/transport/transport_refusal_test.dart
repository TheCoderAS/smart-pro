import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/transport/control_transport.dart';
import 'package:unisync/core/transport/transport_coordinator.dart';
import 'package:unisync/core/transport/transport_manager.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('no session ⇒ Bluetooth is refused, and nothing is persisted',
      () async {
    // Login is Wi-Fi-only by design, so Bluetooth has no session to carry.
    // The story rules out a half-switched state: the preference must not be
    // written for a switch that didn't happen, or the next launch would
    // reapply it.
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final refusal =
        await c.read(transportCoordinatorProvider).choose(
              TransportPreference.bluetooth,
            );

    expect(refusal, TransportRefusal.needsWifiLogin);
    expect(c.read(transportPreferenceProvider), TransportPreference.auto);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TransportPreferenceNotifier.key), isNull);
  });

  test('a refusal explains itself rather than failing silently', () {
    for (final r in TransportRefusal.values) {
      expect(r.message, isNotEmpty);
    }
    expect(
      TransportRefusal.needsWifiLogin.message,
      contains('Wi-Fi'),
    );
    expect(
      TransportRefusal.permissionDenied.message,
      contains('permission'),
    );
  });

  test('Wi-Fi is never refused', () async {
    // Whatever else is wrong, the way back to Wi-Fi has to stay open —
    // every dead end in the app offers it.
    final c = ProviderContainer(
      overrides: [tokenProvider.overrideWith(() => _Token())],
    );
    addTearDown(c.dispose);

    expect(
      await c.read(transportCoordinatorProvider).canUseBle(),
      isNot(TransportRefusal.needsWifiLogin),
    );
  });
}

class _Token extends TokenNotifier {
  @override
  String? build() => 'deadbeefdeadbeefdeadbeefdeadbeef';
}
