import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/db/local_store.dart';
import 'data_portability.dart';

/// On-device automatic backups: a rolling set of full JSON snapshots written to
/// the app's documents directory. Stands in for Cashew's cloud (Drive) sync
/// until cloud credentials are configured; pairs with the manual share/export.
class AutoBackup {
  AutoBackup._();

  static const _keepLast = 7;
  static const _minIntervalHours = 12;

  static String _meta(String key) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  static void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  static bool get enabled => _meta('auto_backup_enabled') == 'true';

  static void setEnabled(bool v) => _set('auto_backup_enabled', v ? 'true' : 'false');

  static DateTime? get lastBackupAt => DateTime.tryParse(_meta('auto_backup_at'));

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'nexo_backups'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Runs a backup if enabled and the last one is older than the interval.
  /// Safe to call at startup; never throws.
  static Future<void> maybeRunOnLaunch() async {
    try {
      if (!enabled) return;
      final last = lastBackupAt;
      if (last != null && DateTime.now().difference(last).inHours < _minIntervalHours) return;
      await runNow();
    } catch (e) {
      if (kDebugMode) debugPrint('auto-backup launch failed: $e');
    }
  }

  /// Writes a snapshot now and prunes old ones. Returns the file path.
  static Future<String> runNow() async {
    final json = DataPortability.backupJson(generatedAtIso: DateTime.now().toIso8601String());
    final dir = await _dir();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File(p.join(dir.path, 'nexo-auto-$stamp.json'));
    await file.writeAsString(json);
    _set('auto_backup_at', DateTime.now().toIso8601String());
    await _prune();
    return file.path;
  }

  static Future<List<File>> listBackups() async {
    final dir = await _dir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static Future<void> _prune() async {
    final files = await listBackups();
    for (final f in files.skip(_keepLast)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}
