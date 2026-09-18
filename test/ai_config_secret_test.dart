import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/ai/ai_config.dart';
import 'package:nexo/core/ai/ai_provider_catalog.dart';
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

void main() {
  setUpAll(() {
    LocalStore.db = sqlite3.openInMemory();
    LocalStore.applySchema(LocalStore.db);
  });

  setUp(() => LocalStore.db.execute('DELETE FROM app_meta'));

  String? metaValue(String key) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  test('migrates a plaintext key found in the DB blob into the secret store', () async {
    final withKey = presetById('anthropic').toProfile().copyWith(apiKey: 'sk-plain');
    LocalStore.db.execute(
      "INSERT INTO app_meta (key, value) VALUES ('ai_providers', ?)",
      [jsonEncode([withKey.toJson()])],
    );

    final secrets = FakeSecretStore();
    final n = AiConfigNotifier(secrets: secrets);
    addTearDown(n.dispose);
    await n.ready;

    // Usable in memory, durable only in the keychain, gone from the DB.
    expect(n.state.profile('anthropic').apiKey, 'sk-plain');
    expect(secrets.map['ai_key_anthropic'], 'sk-plain');
    expect(metaValue('ai_providers'), isNot(contains('sk-plain')));
  });

  test('migrates the legacy single-provider key and deletes its rows', () async {
    LocalStore.db.execute(
      "INSERT INTO app_meta (key, value) VALUES ('ai_api_key', 'sk-legacy'), ('ai_model', 'claude-x')",
    );

    final secrets = FakeSecretStore();
    final n = AiConfigNotifier(secrets: secrets);
    addTearDown(n.dispose);
    await n.ready;

    expect(secrets.map['ai_key_anthropic'], 'sk-legacy');
    expect(n.state.profile('anthropic').model, 'claude-x');
    expect(metaValue('ai_api_key'), isNull);
    expect(metaValue('ai_providers'), isNot(contains('sk-legacy')));
  });

  test('updateProvider writes the key to the secret store, never to the DB', () async {
    final secrets = FakeSecretStore();
    final n = AiConfigNotifier(secrets: secrets);
    addTearDown(n.dispose);
    await n.ready;

    await n.updateProvider('anthropic', apiKey: 'sk-new', model: 'claude-y');

    expect(n.state.profile('anthropic').apiKey, 'sk-new');
    expect(secrets.map['ai_key_anthropic'], 'sk-new');
    final blob = metaValue('ai_providers');
    expect(blob, isNot(contains('sk-new')));
    expect(blob, contains('claude-y'));

    // Clearing the key removes it from the keychain too.
    await n.updateProvider('anthropic', apiKey: '');
    expect(secrets.map.containsKey('ai_key_anthropic'), isFalse);
  });

  test('loads the key back from the secret store on a fresh notifier', () async {
    final secrets = FakeSecretStore()..map['ai_key_anthropic'] = 'sk-stored';

    final n = AiConfigNotifier(secrets: secrets);
    addTearDown(n.dispose);
    await n.ready;

    expect(n.state.profile('anthropic').apiKey, 'sk-stored');
    // Nothing to migrate: the DB stays free of provider rows with keys.
    expect(metaValue('ai_providers') ?? '', isNot(contains('sk-stored')));
  });
}
