import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/ai/llm_client.dart';
import '../../../core/ai/on_device_gemma_client.dart';
import '../../../core/ai/on_device_models.dart';
import '../../../core/util/ids.dart';
import '../../accounts/domain/account.dart';
import '../../ai/domain/ai_providers.dart';
import '../../ai/domain/ai_services.dart';
import '../../capture/domain/merchant_memory.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/capture_layout.dart';
import '../../transactions/domain/capture_layout_provider.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../../data/domain/data_portability.dart';
import 'document.dart';
import 'document_transaction.dart';
import 'document_transactions_repository.dart';
import 'documents_provider.dart';
import 'ocr_service.dart';
import 'remote_ocr_client.dart';

/// Max statement pages we rasterize+send per document (memory + token guard).
const _kMaxPdfPages = 40;

/// Orchestrates extracting staged drafts from a document by source type:
/// image/pdf → AI vision, csv → deterministic parse, text → AI text parse.
/// Each extracted row gets a MerchantMemory category override, catalog name→id
/// resolution and a dedupe flag before it is written to `document_transactions`.
class DocumentParser {
  DocumentParser(this.ref);

  final Ref ref;

  /// Parses [doc] and writes the resulting drafts. Updates the document's
  /// status/counts and refreshes the watching providers. [engineOverride]
  /// forces a specific engine (used when the "ask each time" setting resolves a
  /// choice in the UI); otherwise the configured document engine is used.
  Future<void> parseAndStage(NexoDocument doc, {DocumentEngine? engineOverride}) async {
    final stagingRepo = ref.read(documentTransactionsRepositoryProvider);
    final docsRepo = ref.read(documentsRepositoryProvider);

    try {
      final rows = <DocumentTransaction>[];
      var failedParts = 0;
      String engineLabel = 'csv';

      if (doc.sourceType == DocumentSourceType.csv) {
        rows.addAll(await _parseCsv(doc));
      } else {
        final setting = engineOverride ?? ref.read(captureLayoutProvider).documentEngine;
        final ai = await _resolveEngine(setting);
        if (ai == null) {
          docsRepo.updateStatus(doc.id, DocumentStatus.failed,
              error: setting == DocumentEngine.onDevice
                  ? 'Descarga un modelo on-device en Ajustes → IA para procesar sin conexión.'
                  : 'Activa la IA en Ajustes para procesar este documento.');
          ref.read(documentsProvider.notifier).load();
          return;
        }
        engineLabel = ai.client.label;
        final result = switch (doc.sourceType) {
          DocumentSourceType.image => await _parseImage(doc, ai),
          DocumentSourceType.pdf => await _parsePdf(doc, ai),
          DocumentSourceType.text => await _parseText(doc, ai),
          DocumentSourceType.csv => (rows: <DocumentTransaction>[], failed: 0),
        };
        rows.addAll(result.rows);
        failedParts = result.failed;
      }

      stagingRepo.insertBatch(rows);
      final status = rows.isEmpty
          ? (failedParts > 0 ? DocumentStatus.failed : DocumentStatus.parsed)
          : (failedParts > 0 ? DocumentStatus.partial : DocumentStatus.parsed);
      docsRepo.updateStatus(
        doc.id,
        status,
        engine: engineLabel,
        error: rows.isEmpty && failedParts > 0
            ? 'No se pudieron leer los movimientos.'
            : null,
      );
      docsRepo.setCounts(doc.id, txCount: rows.length);
    } catch (e) {
      docsRepo.updateStatus(doc.id, DocumentStatus.failed, error: e.toString());
    }

    ref.read(documentsProvider.notifier).load();
    ref.read(documentTransactionsProvider(doc.id).notifier).load();
  }

  /// Picks the AI service per the document engine setting. "ask each time" is
  /// resolved upstream in the UI, so here it behaves like the configured one.
  Future<AiServices?> _resolveEngine(DocumentEngine setting) async {
    switch (setting) {
      case DocumentEngine.onDevice:
        return _onDeviceServices();
      case DocumentEngine.configuredProvider:
      case DocumentEngine.askEachTime:
        return ref.read(aiServicesProvider);
    }
  }

  /// Builds an AiServices over a downloaded on-device Gemma model (preferring a
  /// vision-capable one), or null if none is installed.
  Future<AiServices?> _onDeviceServices() async {
    try {
      final installed = await OnDeviceGemma.installed();
      OnDeviceModel? chosen;
      for (final m in kOnDeviceModels) {
        if (!installed.contains(m.id)) continue;
        chosen ??= m;
        if (m.supportsVision) {
          chosen = m;
          break;
        }
      }
      if (chosen == null) return null;
      return AiServices(OnDeviceGemmaClient(modelId: chosen.id));
    } catch (_) {
      return null;
    }
  }

  // ---- per-source extraction ------------------------------------------------

  Future<List<DocumentTransaction>> _parseCsv(NexoDocument doc) async {
    final content = await _readText(doc);
    if (content == null || content.trim().isEmpty) return const [];
    final parsed = DataPortability.parseTransactionsCsv(content);
    final ctx = _stagingContext(doc);
    return [
      for (final r in parsed)
        _stage(
          doc,
          ParsedTransaction(
            amount: r.amount,
            type: r.type,
            title: r.title,
            categoryName: r.category,
            accountName: r.account,
            currency: r.currency,
            date: r.date,
            note: r.note,
            confidence: 1.0,
          ),
          ctx,
          line: r.line,
        ),
    ];
  }

  Future<({List<DocumentTransaction> rows, int failed})> _parseImage(
      NexoDocument doc, AiServices ai) async {
    final path = doc.storedPath;
    if (path == null) return (rows: <DocumentTransaction>[], failed: 1);

    final ocrMode = ref.read(captureLayoutProvider).documentOcr;

    // Remote SOTA OCR endpoint (Mistral-OCR-compatible) → markdown → AI text.
    if (ocrMode == DocumentOcr.remoteOcr) {
      return _remoteOcrStage(doc, path, doc.mimeType ?? 'image/jpeg', ai);
    }

    // On-device OCR (default): recognize the text on the phone, then let the AI
    // structure it — the same text path that already works reliably.
    if (ocrMode == DocumentOcr.onDeviceOcr) {
      try {
        final text = await ref.read(ocrServiceProvider).ocrImageFile(path);
        ref.read(documentsRepositoryProvider).setNote(doc.id, text.trim().isEmpty ? null : text);
        if (text.trim().isEmpty) return (rows: <DocumentTransaction>[], failed: 1);
        return _stageFromText(doc, text, ai, page: 1);
      } catch (_) {
        return (rows: <DocumentTransaction>[], failed: 1);
      }
    }

    // AI vision: send the image straight to a vision-capable provider.
    final bytes = await File(path).readAsBytes();
    final image = AiImage(
      base64Data: base64Encode(bytes),
      mediaType: doc.mimeType ?? 'image/jpeg',
    );
    final cat = ref.read(aiCatalogProvider);
    try {
      final parsed = await ai.parseStatementImages(
        [image],
        categories: [for (final c in cat.categories) c.name],
        accounts: [for (final a in cat.accounts) a.name],
      );
      final ctx = _stagingContext(doc);
      return (rows: [for (final p in parsed) _stage(doc, p, ctx, page: 1)], failed: 0);
    } on AiException {
      return (rows: <DocumentTransaction>[], failed: 1);
    }
  }

  Future<({List<DocumentTransaction> rows, int failed})> _parsePdf(
      NexoDocument doc, AiServices ai) async {
    final path = doc.storedPath;
    if (path == null) return (rows: <DocumentTransaction>[], failed: 1);

    final ocrMode = ref.read(captureLayoutProvider).documentOcr;

    // Remote SOTA OCR: send the whole PDF (it handles multi-page natively).
    if (ocrMode == DocumentOcr.remoteOcr) {
      return _remoteOcrStage(doc, path, 'application/pdf', ai);
    }

    final document = await PdfDocument.openFile(path);
    try {
      final total = min(document.pagesCount, _kMaxPdfPages);
      // Record pages actually processed (capped), not the document's full count.
      ref.read(documentsRepositoryProvider).setCounts(doc.id, pageCount: total);

      // On-device OCR: rasterize each page, recognize text on the phone, then
      // hand the combined text to the AI text extractor.
      if (ocrMode == DocumentOcr.onDeviceOcr) {
        final ocr = ref.read(ocrServiceProvider);
        final tmpDir = await getTemporaryDirectory();
        final buffer = StringBuffer();
        var failed = 0;
        for (var i = 1; i <= total; i++) {
          try {
            final bytes = await _renderPage(document, i);
            if (bytes == null) {
              failed++;
              continue;
            }
            final f = File(p.join(tmpDir.path, 'ocr_${doc.id}_$i.png'));
            try {
              await f.writeAsBytes(bytes);
              final text = await ocr.ocrImageFile(f.path);
              if (text.trim().isNotEmpty) {
                buffer.writeln(text);
              } else {
                // Page rendered but OCR found no text → count it so the
                // document status reflects the partial read.
                failed++;
              }
            } finally {
              try {
                await f.delete();
              } catch (_) {/* best-effort */}
            }
          } catch (_) {
            failed++;
          }
        }
        final ocrText = buffer.toString();
        ref.read(documentsRepositoryProvider).setNote(doc.id, ocrText.trim().isEmpty ? null : ocrText);
        final res = await _stageFromText(doc, ocrText, ai);
        return (rows: res.rows, failed: failed + res.failed);
      }

      // AI vision: one rasterized page per vision call.
      final cat = ref.read(aiCatalogProvider);
      final cats = [for (final c in cat.categories) c.name];
      final accts = [for (final a in cat.accounts) a.name];
      final ctx = _stagingContext(doc);
      final out = <DocumentTransaction>[];
      var failed = 0;
      for (var i = 1; i <= total; i++) {
        try {
          final bytes = await _renderPage(document, i);
          if (bytes == null) {
            failed++;
            continue;
          }
          final image = AiImage(base64Data: base64Encode(bytes), mediaType: 'image/png');
          final parsed = await ai.parseStatementImages([image], categories: cats, accounts: accts);
          out.addAll([for (final p in parsed) _stage(doc, p, ctx, page: i)]);
        } catch (_) {
          failed++;
        }
      }
      return (rows: out, failed: failed);
    } finally {
      await document.close();
    }
  }

  /// Renders one PDF page to PNG bytes at a capped width (~1600px), or null.
  Future<Uint8List?> _renderPage(PdfDocument document, int pageNumber) async {
    final page = await document.getPage(pageNumber);
    try {
      final targetW = min(1600.0, page.width * 2);
      final scale = targetW / page.width;
      final rendered = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      return rendered?.bytes;
    } finally {
      await page.close();
    }
  }

  Future<({List<DocumentTransaction> rows, int failed})> _parseText(
      NexoDocument doc, AiServices ai) async {
    final content = await _readText(doc);
    return _stageFromText(doc, content ?? '', ai);
  }

  /// Sends the document to a Mistral-OCR-compatible endpoint, stores the
  /// returned markdown, then structures it with the AI. Throws (caught by
  /// parseAndStage, which records the message) when the endpoint is missing or
  /// fails — remote OCR is a single call for the whole document.
  Future<({List<DocumentTransaction> rows, int failed})> _remoteOcrStage(
      NexoDocument doc, String path, String mimeType, AiServices ai) async {
    final cfg = ref.read(captureLayoutProvider);
    if (cfg.ocrEndpoint.trim().isEmpty) {
      throw RemoteOcrException(
          'Configura la URL del endpoint OCR en Ajustes → Captura y layout.');
    }
    // Guard against OOM / oversized payloads (base64 adds ~33%).
    const maxBytes = 50 * 1024 * 1024;
    final file = File(path);
    if (await file.length() > maxBytes) {
      throw RemoteOcrException('El archivo supera el máximo para OCR remoto (~50 MB).');
    }
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw RemoteOcrException('No se pudo leer el archivo: $e');
    }
    final text = await ref.read(remoteOcrClientProvider).recognize(
          baseUrl: cfg.ocrEndpoint,
          apiKey: cfg.ocrApiKey,
          model: cfg.ocrModel,
          bytes: bytes,
          mimeType: mimeType,
        );
    ref.read(documentsRepositoryProvider).setNote(doc.id, text.trim().isEmpty ? null : text);
    if (text.trim().isEmpty) return (rows: <DocumentTransaction>[], failed: 1);
    return _stageFromText(doc, text, ai);
  }

  /// Shared text→drafts path: chunk the text, run the AI text extractor per
  /// chunk, and stage the results. Reused by the text source and by on-device
  /// OCR of images/PDFs.
  Future<({List<DocumentTransaction> rows, int failed})> _stageFromText(
      NexoDocument doc, String content, AiServices ai,
      {int? page}) async {
    if (content.trim().isEmpty) return (rows: <DocumentTransaction>[], failed: 0);
    final cat = ref.read(aiCatalogProvider);
    final cats = [for (final c in cat.categories) c.name];
    final accts = [for (final a in cat.accounts) a.name];
    final ctx = _stagingContext(doc);

    final chunks = _chunkLines(content);
    final out = <DocumentTransaction>[];
    var failed = 0;
    var lineOffset = 0;
    for (final chunk in chunks) {
      final chunkLines = '\n'.allMatches(chunk).length + 1;
      try {
        final parsed = await ai.parseStatementText(chunk, categories: cats, accounts: accts);
        out.addAll([for (final pt in parsed) _stage(doc, pt, ctx, page: page, line: lineOffset + 1)]);
      } catch (_) {
        failed++;
      }
      lineOffset += chunkLines;
    }
    return (rows: out, failed: failed);
  }

  // ---- helpers --------------------------------------------------------------

  /// Reads the document's source text (inline note for pasted text, otherwise
  /// the stored file). Used by CSV + text paths.
  Future<String?> _readText(NexoDocument doc) async {
    if (doc.storedPath == null) return doc.note;
    try {
      final bytes = await File(doc.storedPath!).readAsBytes();
      try {
        return utf8.decode(bytes); // strict first (correct for UTF-8 files)
      } on FormatException {
        return latin1.decode(bytes); // Windows-1252/Latin-1 bank exports
      }
    } catch (_) {
      return doc.note; // genuine IO error
    }
  }

  List<String> _chunkLines(String text, {int linesPerChunk = 80}) {
    final lines = text.split('\n');
    if (lines.length <= linesPerChunk) return [text];
    final chunks = <String>[];
    for (var i = 0; i < lines.length; i += linesPerChunk) {
      chunks.add(lines.sublist(i, min(i + linesPerChunk, lines.length)).join('\n'));
    }
    return chunks;
  }

  _StagingContext _stagingContext(NexoDocument doc) {
    final catalog = ref.read(aiCatalogProvider);
    final mem = ref.read(merchantMemoryProvider);
    final stagingRepo = ref.read(documentTransactionsRepositoryProvider);
    final existing = <String>{
      for (final t in ref.read(transactionsProvider))
        DocumentTransaction.computeDedupeHash(
          date: t.date,
          amount: t.amount,
          title: t.title,
          type: t.type,
        ),
    };
    return _StagingContext(
      categories: catalog.categories,
      accounts: catalog.accounts,
      mem: mem,
      stagingRepo: stagingRepo,
      existingHashes: existing,
    );
  }

  DocumentTransaction _stage(
    NexoDocument doc,
    ParsedTransaction p,
    _StagingContext ctx, {
    int? page,
    int? line,
  }) {
    // Deterministic/learned category wins over the AI's guess.
    var categoryName = p.categoryName;
    String? learnedId;
    final learned = ctx.mem.lookup(p.title);
    if (learned != null) {
      categoryName = learned.name;
      learnedId = learned.id;
    }
    final resolved = resolveCatalog(
      categoryName,
      p.accountName,
      categories: ctx.categories,
      accounts: ctx.accounts,
    );
    final cat = resolved.category;
    final acc = resolved.account;
    final now = DateTime.now();
    final date = p.date ?? now;

    final hash = DocumentTransaction.computeDedupeHash(
      date: date,
      amount: p.amount,
      title: p.title,
      type: p.type,
    );
    final isDuplicate = ctx.existingHashes.contains(hash) ||
        ctx.stagingRepo.dedupeExists(hash, exceptDocumentId: doc.id);

    return DocumentTransaction(
      id: newId('dtx'),
      documentId: doc.id,
      title: p.title,
      amount: p.amount,
      category: cat?.name ?? categoryName ?? 'Sin categoría',
      categoryId: cat?.id ?? learnedId,
      date: date,
      type: p.type,
      account: acc?.name ?? p.accountName ?? 'Efectivo',
      accountId: acc?.id,
      currency: p.currency,
      note: p.note,
      confidence: p.confidence ?? 0,
      selected: !isDuplicate,
      status: isDuplicate ? DocTxStatus.duplicate : DocTxStatus.staged,
      dedupeHash: hash,
      sourcePage: page,
      sourceLine: line,
      createdAt: now,
    );
  }
}

class _StagingContext {
  _StagingContext({
    required this.categories,
    required this.accounts,
    required this.mem,
    required this.stagingRepo,
    required this.existingHashes,
  });

  final List<Category> categories;
  final List<Account> accounts;
  final MerchantMemory mem;
  final DocumentTransactionsRepository stagingRepo;
  final Set<String> existingHashes;
}

final documentParserProvider = Provider<DocumentParser>((ref) => DocumentParser(ref));
