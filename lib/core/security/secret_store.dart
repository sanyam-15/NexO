import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal async key-value contract for secrets, so domain code doesn't bind
/// to the plugin and tests can inject an in-memory fake.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Platform-backed store: Android Keystore / iOS Keychain. Secrets kept here
/// never touch the SQLite file, so they stay out of DB copies and backups.
class KeychainSecretStore implements SecretStore {
  const KeychainSecretStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
