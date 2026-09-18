import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';

void main() {
  setUp(() {
    LocalStore.startupError = null;
  });

  Set<String> tableNames(db) => db
      .select("SELECT name FROM sqlite_master WHERE type='table'")
      .map<String>((r) => r['name'] as String)
      .toSet();

  test('opens and migrates a real file database without flagging an error', () {
    final dir = Directory.systemTemp.createTempSync('nexo_guard_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final db = LocalStore.openGuarded('${dir.path}/nexo.db');
    addTearDown(db.close);

    expect(LocalStore.startupError, isNull);
    expect(tableNames(db), contains('transactions'));
    expect(File('${dir.path}/nexo.db').existsSync(), isTrue);
  });

  test('falls back to a schema-complete in-memory db when open fails', () {
    final db = LocalStore.openGuarded('/nonexistent-dir-xyz/nexo.db');
    addTearDown(db.close);

    expect(LocalStore.startupError, isNotNull);
    // The fallback must still carry the full schema so providers can run.
    expect(tableNames(db), containsAll(['transactions', 'accounts', 'app_meta']));
  });
}
