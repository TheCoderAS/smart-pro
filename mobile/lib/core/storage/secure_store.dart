import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure key-value store for secrets: session tokens (one per master
/// UID) and, if the user opts in, remembered device passwords.
/// Keychain on iOS, EncryptedSharedPreferences on Android.
///
/// Recovery keys are deliberately NOT storable — per PLAN.md §11 the
/// user re-enters the recovery key on each attempt.
final secureStoreProvider = Provider<SecureStore>((ref) {
  return SecureStore(const FlutterSecureStorage());
});

class SecureStore {
  const SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  static String _tokenKey(String masterUid) => 'token.$masterUid';
  static String _passwordKey(String masterUid) => 'password.$masterUid';

  Future<String?> readToken(String masterUid) =>
      _storage.read(key: _tokenKey(masterUid));

  Future<void> writeToken(String masterUid, String token) =>
      _storage.write(key: _tokenKey(masterUid), value: token);

  Future<void> deleteToken(String masterUid) =>
      _storage.delete(key: _tokenKey(masterUid));

  Future<String?> readPassword(String masterUid) =>
      _storage.read(key: _passwordKey(masterUid));

  Future<void> writePassword(String masterUid, String password) =>
      _storage.write(key: _passwordKey(masterUid), value: password);

  Future<void> deletePassword(String masterUid) =>
      _storage.delete(key: _passwordKey(masterUid));

  /// Removes every secret for a master — used by "remove this master
  /// from the app" in Settings.
  Future<void> purgeMaster(String masterUid) async {
    await deleteToken(masterUid);
    await deletePassword(masterUid);
  }
}
