import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'document.dart';
import 'document_transaction.dart';
import 'document_transactions_repository.dart';
import 'documents_repository.dart';

final documentsRepositoryProvider =
    Provider<DocumentsRepository>((ref) => const DocumentsRepository());

final documentTransactionsRepositoryProvider =
    Provider<DocumentTransactionsRepository>((ref) => const DocumentTransactionsRepository());

class DocumentsNotifier extends StateNotifier<List<NexoDocument>> {
  DocumentsNotifier(this._repo) : super([]) {
    load();
  }

  final DocumentsRepository _repo;

  void load() => state = _repo.all();

  void upsert(NexoDocument doc) {
    _repo.insert(doc);
    load();
  }

  NexoDocument? byId(String id) => _repo.byId(id);

  /// Deletes the document, its staged drafts and the stored source file.
  Future<void> remove(String id) async {
    final doc = _repo.byId(id);
    _repo.delete(id);
    final path = doc?.storedPath;
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {/* best-effort cleanup */}
    }
    load();
  }
}

final documentsProvider =
    StateNotifierProvider<DocumentsNotifier, List<NexoDocument>>(
  (ref) => DocumentsNotifier(ref.watch(documentsRepositoryProvider)),
);

/// Staged drafts for one document. Family-keyed so each detail screen watches
/// only its own document's drafts.
class DocumentTransactionsNotifier extends StateNotifier<List<DocumentTransaction>> {
  DocumentTransactionsNotifier(this._repo, this.documentId) : super([]) {
    load();
  }

  final DocumentTransactionsRepository _repo;
  final String documentId;

  void load() => state = _repo.forDocument(documentId);

  void update(DocumentTransaction d) {
    _repo.update(d);
    load();
  }

  void setSelected(String id, bool selected) {
    _repo.setSelected(id, selected);
    load();
  }

  void setAllSelected(bool selected, {bool onlyStaged = true}) {
    for (final d in state) {
      if (onlyStaged && d.status != DocTxStatus.staged && d.status != DocTxStatus.duplicate) {
        continue;
      }
      _repo.setSelected(d.id, selected);
    }
    load();
  }

  void deleteBatch(List<String> ids) {
    _repo.deleteBatch(ids);
    load();
  }

  void markImported(String id, String transactionId) {
    _repo.setStatus(id, DocTxStatus.imported, transactionId: transactionId);
    load();
  }

  /// Marks many drafts imported in one transaction, reloading once.
  void markImportedBatch(List<(String draftId, String transactionId)> pairs) {
    _repo.markImportedBatch(pairs);
    load();
  }

  void setStatus(String id, DocTxStatus status) {
    _repo.setStatus(id, status);
    load();
  }
}

final documentTransactionsProvider = StateNotifierProvider.family<
    DocumentTransactionsNotifier, List<DocumentTransaction>, String>(
  (ref, documentId) => DocumentTransactionsNotifier(
    ref.watch(documentTransactionsRepositoryProvider),
    documentId,
  ),
);
