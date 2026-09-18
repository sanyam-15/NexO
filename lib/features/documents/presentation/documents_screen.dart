import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/util/ids.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../../design_system/tokens/ds_radius.dart';
import '../../../design_system/tokens/ds_spacing.dart';
import '../../transactions/domain/capture_layout.dart';
import '../../transactions/domain/capture_layout_provider.dart';
import '../domain/document.dart';
import '../domain/document_parser.dart';
import '../domain/documents_provider.dart';

/// The Documents workspace — upload bank statements / receipts (PDF, image, CSV
/// or pasted text) and turn them into transactions in bulk.
///
/// [embedded] renders just the scrollable body (used as a home tab); otherwise
/// it wraps itself in a Scaffold for the `/documents` route.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);

    final body = <Widget>[
      _UploadCard(onTap: () => _showUploadSheet(context, ref)),
      const SizedBox(height: 16),
      if (docs.isEmpty)
        const DsEmptyState(
          icon: Icons.description_outlined,
          title: 'Sin documentos',
          message:
              'Sube un estado de cuenta (PDF, imagen o CSV) o pega texto para extraer y registrar movimientos en lote.',
        )
      else
        ...docs.map((d) => _DocumentTile(doc: d)),
    ];

    if (embedded) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
        children: body,
      );
    }
    return DsScreenScaffold(
      title: 'Documentos',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(context, ref),
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Subir'),
      ),
      children: body,
    );
  }

  Future<void> _showUploadSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        Widget option(IconData icon, String title, String subtitle, VoidCallback onTap) {
          return DsListTile(
            icon: icon,
            title: title,
            subtitle: subtitle,
            onTap: () {
              Navigator.pop(sheetCtx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DsSpacing.lg, DsSpacing.xxs, DsSpacing.lg, DsSpacing.xs),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Subir documento',
                      style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ),
              ),
              option(Icons.picture_as_pdf_rounded, 'PDF o CSV',
                  'Estado de cuenta en PDF o exportación CSV del banco', () => _pickFile(context, ref)),
              option(Icons.photo_library_outlined, 'Imagen de la galería',
                  'Captura o foto de un estado de cuenta / recibo', () => _pickImage(context, ref, ImageSource.gallery)),
              option(Icons.photo_camera_outlined, 'Tomar foto',
                  'Fotografía un estado de cuenta o recibo', () => _pickImage(context, ref, ImageSource.camera)),
              option(Icons.content_paste_rounded, 'Pegar texto',
                  'Pega el texto de los movimientos directamente', () => _pasteText(context, ref)),
              const SizedBox(height: DsSpacing.xs),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'csv'],
      withData: false,
    );
    final files = result?.files;
    final picked = (files != null && files.isNotEmpty) ? files.first : null;
    final path = picked?.path;
    if (picked == null || path == null) return;
    final ext = (picked.extension ?? '').toLowerCase();
    final isCsv = ext == 'csv';
    if (!context.mounted) return;
    await _ingest(
      context,
      ref,
      type: isCsv ? DocumentSourceType.csv : DocumentSourceType.pdf,
      sourcePath: path,
      fileName: picked.name,
      mimeType: isCsv ? 'text/csv' : 'application/pdf',
      sizeBytes: picked.size,
      title: picked.name,
    );
  }

  Future<void> _pickImage(BuildContext context, WidgetRef ref, ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (file == null) return;
    final media = file.mimeType ?? (file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    final size = await File(file.path).length();
    if (!context.mounted) return;
    await _ingest(
      context,
      ref,
      type: DocumentSourceType.image,
      sourcePath: file.path,
      fileName: file.name,
      mimeType: media,
      sizeBytes: size,
      title: file.name,
    );
  }

  Future<void> _pasteText(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Pegar texto'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Pega aquí los movimientos del estado de cuenta…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
              child: const Text('Procesar'),
            ),
          ],
        ),
      );
      if (text == null || text.isEmpty || !context.mounted) return;
      await _ingest(
        context,
        ref,
        type: DocumentSourceType.text,
        rawText: text,
        title: 'Texto · ${DateFormat('d MMM HH:mm', 'es_MX').format(DateTime.now())}',
      );
    } finally {
      controller.dispose();
    }
  }

  /// Persists the document, copies the source file into app storage, navigates
  /// to its detail screen and kicks off parsing in the background.
  Future<void> _ingest(
    BuildContext context,
    WidgetRef ref, {
    required DocumentSourceType type,
    String? sourcePath,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? rawText,
    required String title,
  }) async {
    final id = newId('doc');
    String? storedPath;
    if (sourcePath != null) {
      try {
        final dir = await getApplicationSupportDirectory();
        final docsDir = Directory(p.join(dir.path, 'documents'));
        if (!docsDir.existsSync()) docsDir.createSync(recursive: true);
        final dest = p.join(docsDir.path, '${id}_${fileName ?? p.basename(sourcePath)}');
        await File(sourcePath).copy(dest);
        storedPath = dest;
      } catch (_) {
        storedPath = sourcePath; // fall back to the picker path
      }
    }

    final now = DateTime.now();
    final doc = NexoDocument(
      id: id,
      title: title,
      sourceType: type,
      fileName: fileName,
      storedPath: storedPath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      note: rawText,
      status: DocumentStatus.parsing,
      createdAt: now,
      updatedAt: now,
    );
    ref.read(documentsProvider.notifier).upsert(doc);

    // When the engine is "ask each time", let the user choose cloud vs on-device
    // before sending a (sensitive) document anywhere. CSV needs no AI.
    DocumentEngine? engineOverride;
    final setting = ref.read(captureLayoutProvider).documentEngine;
    if (setting == DocumentEngine.askEachTime && type != DocumentSourceType.csv && context.mounted) {
      engineOverride = await _askEngine(context);
    }

    // Parse in the background; the new document appears in the list with its
    // live status. We intentionally do NOT auto-navigate to the detail screen
    // here: returning from the system file/photo picker can leave the Flutter
    // surface black for a few frames, and pushing a route onto that black frame
    // renders an empty screen. Opening the document from the list paints fine.
    unawaited(ref.read(documentParserProvider).parseAndStage(doc, engineOverride: engineOverride));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Documento agregado · extrayendo movimientos…')),
    );
  }

  Future<DocumentEngine?> _askEngine(BuildContext context) {
    return showDialog<DocumentEngine>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('¿Cómo procesar el documento?'),
        content: const Text('Elige el motor para extraer los movimientos de este documento.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, DocumentEngine.onDevice),
            child: const Text('En el dispositivo'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, DocumentEngine.configuredProvider),
            child: const Text('Proveedor configurado'),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: DsRadius.brMd,
      child: Container(
        padding: const EdgeInsets.all(DsSpacing.md),
        decoration: BoxDecoration(
          borderRadius: DsRadius.brMd,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: scheme.surface.withValues(alpha: 0.4),
              child: Icon(Icons.upload_file_rounded, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Subir documento',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('PDF, imagen, CSV o texto · extrae y registra en lote',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.add_rounded),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.doc});
  final NexoDocument doc;

  IconData get _icon => switch (doc.sourceType) {
        DocumentSourceType.pdf => Icons.picture_as_pdf_rounded,
        DocumentSourceType.image => Icons.image_rounded,
        DocumentSourceType.csv => Icons.table_chart_rounded,
        DocumentSourceType.text => Icons.notes_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = switch (doc.status) {
      DocumentStatus.parsing => 'Procesando…',
      DocumentStatus.failed => doc.error ?? 'Error al procesar',
      _ => '${doc.txCount} movimientos · ${doc.importedCount} importados',
    };

    return Dismissible(
      key: ValueKey(doc.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text('Eliminar documento'),
                content: Text('¿Eliminar "${doc.title}" y sus movimientos sin importar?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Eliminar')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => unawaited(ref.read(documentsProvider.notifier).remove(doc.id)),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      child: DsListTile(
        icon: _icon,
        title: doc.title,
        subtitle: subtitle,
        trailing: doc.status == DocumentStatus.parsing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right_rounded),
        onTap: () => context.pushNamed('document-detail', extra: doc.id),
      ),
    );
  }
}
