import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../accounts/domain/accounts_provider.dart';
import '../../capture/domain/merchant_memory.dart';
import '../../categories/domain/categories_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../domain/document.dart';
import '../domain/document_transaction.dart';
import '../domain/documents_provider.dart';

/// Review + bulk-manage the transactions extracted from one document. The user
/// edits drafts inline, multi-selects, and imports/deletes/bulk-edits them.
class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider);
    NexoDocument? doc;
    for (final d in docs) {
      if (d.id == widget.documentId) {
        doc = d;
        break;
      }
    }
    final drafts = ref.watch(documentTransactionsProvider(widget.documentId));

    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documento')),
        body: const Center(child: Text('Documento no encontrado.')),
      );
    }

    final staged = drafts.where((d) => !d.isImported).toList();
    final imported = drafts.where((d) => d.isImported).toList();
    final selected = staged.where((d) => d.selected).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (staged.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) {
                final notifier = ref.read(documentTransactionsProvider(widget.documentId).notifier);
                if (v == 'all') notifier.setAllSelected(true);
                if (v == 'none') notifier.setAllSelected(false);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Seleccionar todo')),
                PopupMenuItem(value: 'none', child: Text('Quitar selección')),
              ],
            ),
        ],
      ),
      body: doc.status == DocumentStatus.parsing
          ? const _ParsingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 140),
              children: [
                _HeaderCard(doc: doc),
                const SizedBox(height: 12),
                if (staged.isEmpty && imported.isEmpty)
                  _EmptyExtraction(doc: doc)
                else ...[
                  if (staged.isNotEmpty) ...[
                    _SectionLabel(text: 'Por importar (${staged.length})'),
                    ...staged.map((d) => _DraftTile(
                          draft: d,
                          onToggle: () => ref
                              .read(documentTransactionsProvider(widget.documentId).notifier)
                              .setSelected(d.id, !d.selected),
                          onEdit: () => _editDraft(d),
                        )),
                  ],
                  if (imported.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _SectionLabel(text: 'Importados (${imported.length})'),
                    ...imported.map((d) => _DraftTile(
                          draft: d,
                          onToggle: null,
                          onEdit: null,
                          onUndo: () => _undoImport(d),
                        )),
                  ],
                ],
              ],
            ),
      bottomNavigationBar: staged.isEmpty
          ? null
          : _ActionBar(
              selectedCount: selected.length,
              busy: _busy,
              onImport: selected.isEmpty ? null : () => _importSelected(selected),
              onDelete: selected.isEmpty ? null : () => _deleteSelected(selected),
              onBulkEdit: selected.isEmpty ? null : () => _bulkEdit(selected),
            ),
    );
  }

  // ---- actions --------------------------------------------------------------

  Future<void> _importSelected(List<DocumentTransaction> selected) async {
    setState(() => _busy = true);
    try {
      final entries = <FinanceEntry>[];
      final pairs = <(String draftId, String txId)>[];
      for (final d in selected) {
        final entry = d.toFinanceEntry();
        entries.add(entry);
        pairs.add((d.id, entry.id));
      }
      // Both writes are transactional; the staging update reloads once.
      ref.read(transactionsProvider.notifier).addBatch(entries);
      ref.read(documentTransactionsProvider(widget.documentId).notifier).markImportedBatch(pairs);

      final mem = ref.read(merchantMemoryProvider);
      for (final d in selected) {
        mem.learn(d.title, categoryId: d.categoryId, categoryName: d.category);
      }
      _refreshDocCounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Importados ${selected.length} movimientos')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected(List<DocumentTransaction> selected) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Eliminar borradores'),
        content: Text('¿Eliminar ${selected.length} movimientos sin importar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(documentTransactionsProvider(widget.documentId).notifier).deleteBatch([for (final d in selected) d.id]);
    _refreshDocCounts();
  }

  Future<void> _bulkEdit(List<DocumentTransaction> selected) async {
    final categories = ref.read(activeCategoriesProvider);
    final accounts = ref.read(activeAccountsProvider);
    final result = await showModalBottomSheet<({String? categoryId, String? categoryName, String? accountId, String? accountName, EntryType? type})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BulkEditSheet(
        categories: [for (final c in categories) (id: c.id, name: c.name)],
        accounts: [for (final a in accounts) (id: a.id, name: a.name)],
      ),
    );
    if (result == null) return;
    final notifier = ref.read(documentTransactionsProvider(widget.documentId).notifier);
    for (final d in selected) {
      notifier.update(d.copyWith(
        category: result.categoryName,
        categoryId: result.categoryId,
        account: result.accountName,
        accountId: result.accountId,
        type: result.type,
      ));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Actualizados ${selected.length} movimientos')),
      );
    }
  }

  Future<void> _undoImport(DocumentTransaction d) async {
    final txId = d.transactionId;
    if (txId != null) ref.read(transactionsProvider.notifier).remove(txId);
    ref.read(documentTransactionsProvider(widget.documentId).notifier).setStatus(d.id, DocTxStatus.staged);
    _refreshDocCounts();
  }

  Future<void> _editDraft(DocumentTransaction d) async {
    final categories = ref.read(activeCategoriesProvider);
    final accounts = ref.read(activeAccountsProvider);
    final updated = await showModalBottomSheet<DocumentTransaction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EditDraftSheet(
        draft: d,
        categories: [for (final c in categories) (id: c.id, name: c.name)],
        accounts: [for (final a in accounts) (id: a.id, name: a.name)],
      ),
    );
    if (updated != null) {
      ref.read(documentTransactionsProvider(widget.documentId).notifier).update(updated);
    }
  }

  /// Recomputes the document's tx/imported counts + status from its drafts.
  void _refreshDocCounts() {
    final drafts = ref.read(documentTransactionsProvider(widget.documentId));
    final active = drafts.where((d) => d.status != DocTxStatus.discarded).toList();
    final importedCount = active.where((d) => d.isImported).length;
    final repo = ref.read(documentsRepositoryProvider);
    repo.setCounts(widget.documentId, txCount: active.length, importedCount: importedCount);
    final status = active.isEmpty
        ? DocumentStatus.parsed
        : importedCount == active.length
            ? DocumentStatus.imported
            : importedCount > 0
                ? DocumentStatus.partial
                : DocumentStatus.parsed;
    repo.updateStatus(widget.documentId, status);
    ref.read(documentsProvider.notifier).load();
  }
}

// ---- widgets ----------------------------------------------------------------

class _ParsingView extends StatelessWidget {
  const _ParsingView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Extrayendo movimientos…'),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.doc});
  final NexoDocument doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = doc.txCount - doc.importedCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Stat(label: 'Extraídos', value: '${doc.txCount}'),
                _Stat(label: 'Por importar', value: '$pending'),
                _Stat(label: 'Importados', value: '${doc.importedCount}'),
              ],
            ),
            if (doc.status == DocumentStatus.partial) ...[
              const SizedBox(height: 8),
              Text('Algunas páginas no se pudieron leer por completo.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

class _EmptyExtraction extends StatelessWidget {
  const _EmptyExtraction({required this.doc});
  final NexoDocument doc;
  @override
  Widget build(BuildContext context) {
    final failed = doc.status == DocumentStatus.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(failed ? Icons.error_outline_rounded : Icons.search_off_rounded,
                size: 34, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(failed ? 'No se pudo procesar' : 'Sin movimientos detectados',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(failed ? (doc.error ?? 'Inténtalo con otro documento.') : 'No se encontraron movimientos en el documento.',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    this.onToggle,
    this.onEdit,
    this.onUndo,
  });

  final DocumentTransaction draft;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = draft.type == EntryType.expense;
    final isDuplicate = draft.status == DocTxStatus.duplicate;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: onToggle == null
            ? Icon(Icons.check_circle_rounded, color: scheme.primary)
            : Checkbox(value: draft.selected, onChanged: (_) => onToggle!()),
        title: Text(draft.title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${draft.category} · ${draft.account} · ${DateFormat.yMMMd('es_MX').format(draft.date)}'),
            if (isDuplicate)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Posible duplicado',
                    style: TextStyle(color: scheme.tertiary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isExpense ? '-' : '+'}${formatMoney(draft.amount, currency: draft.currency)}',
              style: TextStyle(fontWeight: FontWeight.w900, color: isExpense ? scheme.error : scheme.primary),
            ),
            if (onEdit != null)
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit, tooltip: 'Editar')
            else if (onUndo != null)
              IconButton(icon: const Icon(Icons.undo_rounded), onPressed: onUndo, tooltip: 'Deshacer importación'),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.selectedCount,
    required this.busy,
    required this.onImport,
    required this.onDelete,
    required this.onBulkEdit,
  });

  final int selectedCount;
  final bool busy;
  final VoidCallback? onImport;
  final VoidCallback? onDelete;
  final VoidCallback? onBulkEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Eliminar seleccionados',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: busy ? null : onBulkEdit,
                  icon: const Icon(Icons.edit_note_rounded),
                  tooltip: 'Editar en lote',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onImport,
                    icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_done_rounded),
                    label: Text('Importar seleccionados ($selectedCount)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

typedef _NamedRef = ({String id, String name});

String? _idForName(List<_NamedRef> list, String? name) {
  if (name == null) return null;
  for (final e in list) {
    if (e.name == name) return e.id;
  }
  return null;
}

class _EditDraftSheet extends StatefulWidget {
  const _EditDraftSheet({required this.draft, required this.categories, required this.accounts});

  final DocumentTransaction draft;
  final List<_NamedRef> categories;
  final List<_NamedRef> accounts;

  @override
  State<_EditDraftSheet> createState() => _EditDraftSheetState();
}

class _EditDraftSheetState extends State<_EditDraftSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late final TextEditingController _note;
  late EntryType _type;
  late String _category;
  late String? _categoryId;
  late String _account;
  late String? _accountId;
  late String _currency;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _amount = TextEditingController(text: d.amount.toStringAsFixed(2));
    _title = TextEditingController(text: d.title);
    _note = TextEditingController(text: d.note ?? '');
    _type = d.type;
    _category = d.category;
    _categoryId = d.categoryId;
    _account = d.account;
    _accountId = d.accountId;
    _currency = d.currency;
    _date = d.date;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  double? _parseAmount(String input) {
    final raw = input.trim().replaceAll(' ', '');
    if (raw.isEmpty) return null;
    if (raw.contains(',') && raw.contains('.')) return double.tryParse(raw.replaceAll(',', ''));
    if (raw.contains(',')) return double.tryParse(raw.replaceAll(',', '.'));
    return double.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final categoryNames = {widget.draft.category, for (final c in widget.categories) c.name}.toList();
    final accountNames = {widget.draft.account, for (final a in widget.accounts) a.name}.toList();
    final currencyOptions = {_currency, ...supportedCurrencies}.toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Editar movimiento',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            SegmentedButton<EntryType>(
              segments: const [
                ButtonSegment(value: EntryType.expense, label: Text('Gasto'), icon: Icon(Icons.arrow_upward_rounded)),
                ButtonSegment(value: EntryType.income, label: Text('Ingreso'), icon: Icon(Icons.arrow_downward_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto', prefixIcon: Icon(Icons.attach_money_rounded)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Concepto', prefixIcon: Icon(Icons.edit_note_rounded)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              items: [for (final c in categoryNames) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() {
                _category = v ?? _category;
                _categoryId = _idForName(widget.categories, _category);
              }),
              decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.label_outline_rounded)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _account,
              isExpanded: true,
              items: [for (final a in accountNames) DropdownMenuItem(value: a, child: Text(a))],
              onChanged: (v) => setState(() {
                _account = v ?? _account;
                _accountId = _idForName(widget.accounts, _account);
              }),
              decoration: const InputDecoration(labelText: 'Cuenta', prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    items: [for (final c in currencyOptions) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _currency = v ?? _currency),
                    decoration: const InputDecoration(labelText: 'Moneda'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(DateFormat.yMMMd('es_MX').format(_date)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Nota (opcional)', prefixIcon: Icon(Icons.sticky_note_2_outlined)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final amount = _parseAmount(_amount.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ingresa un monto válido')),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    widget.draft.copyWith(
                      amount: amount,
                      title: _title.text.trim().isEmpty ? _category : _title.text.trim(),
                      type: _type,
                      category: _category,
                      categoryId: _categoryId,
                      account: _account,
                      accountId: _accountId,
                      currency: _currency,
                      date: _date,
                      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                    ),
                  );
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkEditSheet extends StatefulWidget {
  const _BulkEditSheet({required this.categories, required this.accounts});

  final List<_NamedRef> categories;
  final List<_NamedRef> accounts;

  @override
  State<_BulkEditSheet> createState() => _BulkEditSheetState();
}

class _BulkEditSheetState extends State<_BulkEditSheet> {
  String? _category;
  String? _account;
  EntryType? _type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Editar en lote',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Aplica a todos los seleccionados. Deja en blanco lo que no quieras cambiar.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            items: [for (final c in widget.categories) DropdownMenuItem(value: c.name, child: Text(c.name))],
            onChanged: (v) => setState(() => _category = v),
            decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.label_outline_rounded)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _account,
            isExpanded: true,
            items: [for (final a in widget.accounts) DropdownMenuItem(value: a.name, child: Text(a.name))],
            onChanged: (v) => setState(() => _account = v),
            decoration: const InputDecoration(labelText: 'Cuenta', prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
          ),
          const SizedBox(height: 10),
          SegmentedButton<EntryType?>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: EntryType.expense, label: Text('Gasto')),
              ButtonSegment(value: EntryType.income, label: Text('Ingreso')),
            ],
            selected: _type == null ? <EntryType?>{} : {_type},
            onSelectionChanged: (s) => setState(() => _type = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final catId = _idForName(widget.categories, _category);
                final accId = _idForName(widget.accounts, _account);
                Navigator.pop(context, (
                  categoryId: catId,
                  categoryName: _category,
                  accountId: accId,
                  accountName: _account,
                  type: _type,
                ));
              },
              child: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    );
  }
}
