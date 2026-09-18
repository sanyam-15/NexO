import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../budgets/domain/budgets_provider.dart';
import '../../categories/domain/categories_provider.dart';
import '../../goals/domain/goals_provider.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../domain/auto_backup.dart';
import '../domain/data_portability.dart';

class DataScreen extends ConsumerWidget {
  const DataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsScreenScaffold(
      title: 'Datos y respaldos',
      children: [
        const DsFeatureHeader(
          title: 'Portabilidad de datos',
          subtitle: 'Exporta a CSV, crea respaldos completos y restaura en otro dispositivo.',
          icon: Icons.import_export_rounded,
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              DsListTile(
                icon: Icons.table_view_rounded,
                title: 'Exportar transacciones (CSV)',
                subtitle: 'Para hojas de cálculo o tu contador',
                trailing: const Icon(Icons.ios_share_rounded),
                onTap: () => _exportCsv(context),
              ),
              DsListTile(
                icon: Icons.backup_rounded,
                title: 'Crear respaldo completo (JSON)',
                subtitle: 'Cuentas, categorías, presupuestos, metas y movimientos',
                trailing: const Icon(Icons.ios_share_rounded),
                onTap: () => _exportBackup(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              DsListTile(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Restaurar respaldo (JSON)',
                subtitle: 'Combina el respaldo con tus datos actuales',
                trailing: const Icon(Icons.folder_open_rounded),
                onTap: () => _restore(context, ref),
              ),
              DsListTile(
                icon: Icons.upload_file_rounded,
                title: 'Importar transacciones (CSV)',
                subtitle: 'Agrega movimientos desde un archivo',
                trailing: const Icon(Icons.folder_open_rounded),
                onTap: () => _importCsv(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _AutoBackupSection(),
        const SizedBox(height: 12),
        Text(
          'Los respaldos se generan en el dispositivo. Guárdalos en un lugar seguro: contienen tu información financiera.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<File> _writeTemp(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString(content);
    return file;
  }

  String _stamp() => DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;

  Future<void> _exportCsv(BuildContext context) async {
    try {
      final csv = DataPortability.transactionsCsv();
      final file = await _writeTemp('nexo-transacciones-${_stamp()}.csv', csv);
      await Share.shareXFiles([XFile(file.path)], text: 'Transacciones de Nexo');
    } catch (e) {
      if (context.mounted) _snack(context, 'No se pudo exportar: $e');
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    try {
      final json = DataPortability.backupJson(generatedAtIso: DateTime.now().toIso8601String());
      final file = await _writeTemp('nexo-respaldo-${_stamp()}.json', json);
      await Share.shareXFiles([XFile(file.path)], text: 'Respaldo completo de Nexo');
    } catch (e) {
      if (context.mounted) _snack(context, 'No se pudo respaldar: $e');
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context, 'Restaurar respaldo',
        'Se combinarán los datos del archivo con los actuales (se sobrescriben registros con el mismo id). ¿Continuar?');
    if (!ok) return;
    try {
      final content = await _pickText(['json']);
      if (content == null) return;
      final result = DataPortability.restoreBackup(content);
      _refreshAll(ref);
      if (context.mounted) _snack(context, result.message);
    } catch (e) {
      if (context.mounted) _snack(context, 'No se pudo restaurar: $e');
    }
  }

  Future<void> _importCsv(BuildContext context, WidgetRef ref) async {
    try {
      final content = await _pickText(['csv', 'txt']);
      if (content == null) return;
      final result = DataPortability.importTransactionsCsv(content);
      _refreshAll(ref);
      if (context.mounted) _snack(context, result.message);
    } catch (e) {
      if (context.mounted) _snack(context, 'No se pudo importar: $e');
    }
  }

  Future<String?> _pickText(List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes != null) return String.fromCharCodes(file.bytes!);
    if (file.path != null) return File(file.path!).readAsString();
    return null;
  }

  void _refreshAll(WidgetRef ref) {
    ref.read(transactionsProvider.notifier).load();
    ref.read(accountsProvider.notifier).load();
    ref.read(categoriesProvider.notifier).load();
    ref.read(budgetsProvider.notifier).load();
    ref.read(goalsProvider.notifier).load();
  }

  void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _AutoBackupSection extends ConsumerStatefulWidget {
  const _AutoBackupSection();

  @override
  ConsumerState<_AutoBackupSection> createState() => _AutoBackupSectionState();
}

class _AutoBackupSectionState extends ConsumerState<_AutoBackupSection> {
  bool _busy = false;

  void _refreshAll() {
    ref.read(transactionsProvider.notifier).load();
    ref.read(accountsProvider.notifier).load();
    ref.read(categoriesProvider.notifier).load();
    ref.read(budgetsProvider.notifier).load();
    ref.read(goalsProvider.notifier).load();
  }

  Future<void> _restore(File file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar respaldo automático'),
        content: const Text('Se combinarán estos datos con los actuales. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final result = DataPortability.restoreBackup(await file.readAsString());
      _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo restaurar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = AutoBackup.lastBackupAt;
    final df = DateFormat('d MMM yyyy · HH:mm', 'es_MX');

    return DsCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_rounded),
            title: const Text('Respaldos automáticos'),
            subtitle: Text(last == null ? 'Genera un respaldo al abrir la app' : 'Último: ${df.format(last)}'),
            value: AutoBackup.enabled,
            onChanged: (v) {
              setState(() => AutoBackup.setEnabled(v));
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _busy = true);
                          try {
                            await AutoBackup.runNow();
                            messenger.showSnackBar(const SnackBar(content: Text('Respaldo creado')));
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Respaldar ahora'),
                ),
              ],
            ),
          ),
          FutureBuilder<List<File>>(
            future: AutoBackup.listBackups(),
            builder: (context, snapshot) {
              final files = snapshot.data ?? const <File>[];
              if (files.isEmpty) return const SizedBox(height: 8);
              return Column(
                children: [
                  const SizedBox(height: 4),
                  ...files.take(5).map((f) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(p.basename(f.path), style: theme.textTheme.bodySmall),
                        trailing: TextButton(onPressed: () => _restore(f), child: const Text('Restaurar')),
                      )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
