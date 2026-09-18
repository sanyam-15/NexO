import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/anthropic_client.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../domain/ai_providers.dart';
import '../domain/ai_services.dart';

Future<void> showAiCaptureSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AiCaptureSheet(),
  );
}

class _AiCaptureSheet extends ConsumerStatefulWidget {
  const _AiCaptureSheet();

  @override
  ConsumerState<_AiCaptureSheet> createState() => _AiCaptureSheetState();
}

class _AiCaptureSheetState extends ConsumerState<_AiCaptureSheet> {
  final _text = TextEditingController();
  bool _loading = false;
  String? _error;
  ParsedTransaction? _draft;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ParsedTransaction> Function(AiServices svc) op) async {
    final svc = ref.read(aiServicesProvider);
    if (svc == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final draft = await op(svc);
      setState(() => _draft = draft);
    } on AiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Algo salió mal: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _interpret() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final catalog = ref.read(aiCatalogProvider);
    await _run((svc) => svc.parseNaturalLanguage(
          text,
          categories: catalog.categories.map((c) => c.name).toList(),
          accounts: catalog.accounts.map((a) => a.name).toList(),
        ));
  }

  Future<void> _scanReceipt() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    final XFile? chosen = file ?? await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1600);
    if (chosen == null) return;
    final bytes = await chosen.readAsBytes();
    final media = chosen.mimeType ?? (chosen.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    final catalog = ref.read(aiCatalogProvider);
    await _run((svc) => svc.parseReceipt(
          AiImage(base64Data: base64Encode(bytes), mediaType: media),
          categories: catalog.categories.map((c) => c.name).toList(),
        ));
  }

  void _save() {
    final draft = _draft;
    if (draft == null) return;
    final catalog = ref.read(aiCatalogProvider);
    final entry = entryFromParsed(draft, categories: catalog.categories, accounts: catalog.accounts);
    ref.read(transactionsProvider.notifier).add(entry);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Guardado: ${entry.title} · ${formatMoney(entry.amount, currency: entry.currency)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final ready = ref.watch(aiReadyProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Captura con IA', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 12),
            if (!ready)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.key_rounded),
                  title: const Text('Configura la IA'),
                  subtitle: const Text('Elige un proveedor (Anthropic, OpenAI-compatible o IA local) en Ajustes → IA para usar esta función.'),
                ),
              )
            else ...[
              TextField(
                controller: _text,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Describe el movimiento',
                  hintText: 'Ej. "café 45 ayer con débito"',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _interpret,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Interpretar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _scanReceipt,
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Recibo'),
                  ),
                ],
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_draft != null) ...[
              const SizedBox(height: 16),
              _DraftPreview(draft: _draft!),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft});
  final ParsedTransaction draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = draft.type == EntryType.expense;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    color: isExpense ? theme.colorScheme.error : theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(draft.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text(
                  formatMoney(draft.amount, currency: draft.currency),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (draft.categoryName != null) Chip(label: Text(draft.categoryName!)),
                if (draft.accountName != null) Chip(label: Text(draft.accountName!)),
                if (draft.date != null)
                  Chip(label: Text('${draft.date!.day}/${draft.date!.month}/${draft.date!.year}')),
              ],
            ),
            if (draft.note != null && draft.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(draft.note!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
