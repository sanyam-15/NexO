import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';
import 'package:nexo/core/security/secret_store.dart';
import 'package:sqlite3/sqlite3.dart';

class FakeSecretStore implements SecretStore {
  final Map<String, String> map = {};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// The `source: sqlcipher` hook user-define in pubspec.yaml gives the test
/// runner SQLCipher too. Probe it so the cipher-dependent group skips loudly
/// (instead of silently passing on plaintext) if that config ever regresses.
bool _cipherAvailable() {
  final probe = sqlite3.openInMemory();
  try {
    return probe.select('PRAGMA cipher_version').isNotEmpty;
  } finally {
    probe.close();
  }
}

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  final hasCipher = _cipherAvailable();

  late Directory dir;
  setUp(() {
    LocalStore.startupError = null;
    dir = Directory.systemTemp.createTempSync('nexo_enc_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('isPlaintextSqlite', () {
    test('recognizes a standard sqlite file', () {
      final path = '${dir.path}/plain.db';
      final db = sqlite3.open(path)
        ..execute('CREATE TABLE t (x)')
        ..close();
      expect(db, isNotNull);
      expect(LocalStore.isPlaintextSqlite(File(path)), isTrue);
    });

    test('rejects non-sqlite and truncated files', () {
      final junk = File('${dir.path}/junk.bin')..writeAsBytesSync(List.filled(64, 0x7f));
      final tiny = File('${dir.path}/tiny.bin')..writeAsBytesSync([1, 2, 3]);
      expect(LocalStore.isPlaintextSqlite(junk), isFalse);
      expect(LocalStore.isPlaintextSqlite(tiny), isFalse);
    });
  });

  group('obtainDbKey', () {
    test('generates a 64-hex key once and returns it stably', () async {
      final secrets = FakeSecretStore();
      final k1 = await LocalStore.obtainDbKey(secrets);
      final k2 = await LocalStore.obtainDbKey(secrets);
      expect(k1, isNotNull);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(k1!), isTrue);
      expect(k2, k1);
      expect(secrets.map['nexo_db_key'], k1);
    });
  });

  group('SQLCipher at rest', () {
    test('encrypts an existing plaintext database in place, keeping its data', () {
      final path = '${dir.path}/nexo.db';
      sqlite3.open(path)
        ..execute("CREATE TABLE legacy (v TEXT); INSERT INTO legacy VALUES ('hola')")
        ..close();
      expect(LocalStore.isPlaintextSqlite(File(path)), isTrue);

      final db = LocalStore.openGuarded(path, hexKey: _key);
      final v = db.select('SELECT v FROM legacy').first['v'];
      db.close();

      expect(LocalStore.startupError, isNull);
      expect(v, 'hola');
      expect(LocalStore.isPlaintextSqlite(File(path)), isFalse);
    });

    test('reopens the encrypted file with the same key', () {
      final path = '${dir.path}/nexo.db';
      final first = LocalStore.openGuarded(path, hexKey: _key);
      first.execute("INSERT INTO app_meta (key, value) VALUES ('probe', 'ok')");
      first.close();

      final second = LocalStore.openGuarded(path, hexKey: _key);
      final v = second.select("SELECT value FROM app_meta WHERE key = 'probe'").first['value'];
      second.close();

      expect(LocalStore.startupError, isNull);
      expect(v, 'ok');
      expect(LocalStore.isPlaintextSqlite(File(path)), isFalse);
    });

    test('wrong key degrades to the in-memory fallback, file left intact', () {
      final path = '${dir.path}/nexo.db';
      LocalStore.openGuarded(path, hexKey: _key).close();
      final sizeBefore = File(path).lengthSync();

      final wrong = LocalStore.openGuarded(path, hexKey: _key.replaceAll('a', 'b'));
      // The fallback still carries the full schema so the app can run.
      final tables = wrong
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'])
          .toSet();
      wrong.close();

      expect(LocalStore.startupError, isNotNull);
      expect(tables, contains('transactions'));
      expect(File(path).lengthSync(), sizeBefore);
    });
  }, skip: hasCipher ? false : 'SQLCipher not available in this build');
}
