import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/on_device_gemma_client.dart';
import '../../../core/db/local_store.dart';
import '../../../core/platform/notification_access.dart';
import '../../../core/util/ids.dart';
import '../../ai/domain/ai_providers.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import 'capture_parser.dart';
import 'capture_repository.dart';
import 'captured_notification.dart';
import 'entity_registry.dart';
import 'merchant_memory.dart';

final captureRepositoryProvider = Provider((ref) => const CaptureRepository());

// ── Settings (enabled + allowlist) ──────────────────────────────────────────

/// User settings for AutoCapture: the master switch and the set of enabled
/// entity ids. Persisted in `app_meta`; every change is mirrored to the native
/// listener's allowlist so it only records apps the user opted into.
class CaptureSettings {
  const CaptureSettings({
    required this.enabled,
    required this.entityIds,
    this.discovery = false,
    this.confirmNotify = false,
  });

  final bool enabled;
  final Set<String> entityIds;

  /// Observe apps NOT in the allowlist that look financial (to surface new apps).
  final bool discovery;

  /// Post the interactive "¿Registrar movimiento?" notification (fingerprint).
  final bool confirmNotify;

  bool isEntityEnabled(String id) => entityIds.contains(id);

  /// Packages the native listener should record (enabled entities only).
  List<String> get activePackages {
    if (!enabled) return const [];
    final out = <String>[];
    for (final e in kCaptureEntities) {
      if (entityIds.contains(e.id)) out.addAll(e.packages);
    }
    return out;
  }

  CaptureSettings copyWith({bool? enabled, Set<String>? entityIds, bool? discovery, bool? confirmNotify}) =>
      CaptureSettings(
        enabled: enabled ?? this.enabled,
        entityIds: entityIds ?? this.entityIds,
        discovery: discovery ?? this.discovery,
        confirmNotify: confirmNotify ?? this.confirmNotify,
      );
}

class CaptureSettingsNotifier extends StateNotifier<CaptureSettings> {
  CaptureSettingsNotifier() : super(const CaptureSettings(enabled: false, entityIds: {})) {
    _load();
  }

  static const _kEnabled = 'capture_enabled';
  static const _kAllowlist = 'capture_allowlist';
  static const _kDiscovery = 'capture_discovery';
  static const _kConfirmNotify = 'capture_confirm_notify';

  String _meta(String key, String fallback) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  void _load() {
    final enabled = _meta(_kEnabled, 'false') == 'true';
    final discovery = _meta(_kDiscovery, 'false') == 'true';
    final confirmNotify = _meta(_kConfirmNotify, 'false') == 'true';
    final raw = _meta(_kAllowlist, '');
    final ids = <String>{};
    if (raw.trim().isNotEmpty) {
      try {
        for (final id in (jsonDecode(raw) as List)) {
          ids.add(id.toString());
        }
      } catch (_) {/* corrupt → empty */}
    }
    state = CaptureSettings(
      enabled: enabled,
      entityIds: ids,
      discovery: discovery,
      confirmNotify: confirmNotify,
    );
    _syncNative();
  }

  void _persist() {
    _set(_kEnabled, state.enabled ? 'true' : 'false');
    _set(_kAllowlist, jsonEncode(state.entityIds.toList()));
    _set(_kDiscovery, state.discovery ? 'true' : 'false');
    _set(_kConfirmNotify, state.confirmNotify ? 'true' : 'false');
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    _persist();
    await _syncNative();
  }

  Future<void> toggleEntity(String id, bool on) async {
    final ids = {...state.entityIds};
    if (on) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    state = state.copyWith(entityIds: ids);
    _persist();
    await _syncNative();
  }

  Future<void> setDiscovery(bool on) async {
    state = state.copyWith(discovery: on);
    _persist();
    await _syncNative();
  }

  Future<void> setConfirmNotify(bool on) async {
    state = state.copyWith(confirmNotify: on);
    _persist();
    await _syncNative();
  }

  Future<void> _syncNative() async {
    await NotificationAccess.setAllowlist(state.activePackages);
    // Discovery / confirm-notify only make sense while capture is enabled.
    await NotificationAccess.setFlags(
      discovery: state.enabled && state.discovery,
      confirmNotify: state.enabled && state.confirmNotify,
    );
  }
}

final captureSettingsProvider =
    StateNotifierProvider<CaptureSettingsNotifier, CaptureSettings>((ref) => CaptureSettingsNotifier());

// ── Inbox (review queue) ─────────────────────────────────────────────────────

/// Outcome of a drain pass, surfaced to the UI.
class DrainResult {
  const DrainResult({
    required this.captured,
    required this.categorized,
    this.confirmed = 0,
    this.dismissed = 0,
  });
  final int captured;
  final int categorized;

  /// Movements confirmed/dismissed via the notification's Sí/No buttons.
  final int confirmed;
  final int dismissed;

  static const empty = DrainResult(captured: 0, categorized: 0);
}

class CaptureInboxNotifier extends StateNotifier<List<CapturedNotification>> {
  CaptureInboxNotifier(this.ref) : super(const []) {
    load();
  }

  final Ref ref;
  CaptureRepository get _repo => ref.read(captureRepositoryProvider);

  bool _draining = false;

  void load() {
    state = _repo.pending();
  }

  /// Drains the native buffer, parses each new notification deterministically,
  /// inserts it into the inbox, applies any Sí/No decisions taken from the
  /// confirm notification, then (best-effort) categorizes the rest on-device.
  Future<DrainResult> drainAndProcess({int maxAiItems = 8}) async {
    // Reentrancy guard: HomeScreen.initState and "Procesar ahora" can both fire
    // a drain; the native drain() is atomic (clears the buffer), so a second
    // concurrent run would race the inbox state. Let only one run at a time.
    if (_draining) return DrainResult.empty;
    _draining = true;
    try {
      return await _drainAndProcess(maxAiItems: maxAiItems);
    } finally {
      _draining = false;
    }
  }

  Future<DrainResult> _drainAndProcess({required int maxAiItems}) async {
    final payload = await NotificationAccess.drain();
    final newOnes = <CapturedNotification>[];
    for (final n in payload.entries) {
      if (_repo.exists(n.id)) continue;
      final captured = _capturedFromRaw(n);
      if (captured == null) continue;
      _repo.insert(captured);
      newOnes.add(captured);
    }

    // Apply Sí/No decisions. A decision can target a capture just inserted above
    // OR one drained on an earlier run (still pending in the inbox).
    var confirmed = 0;
    var dismissed = 0;
    payload.decisions.forEach((id, decision) {
      final row = _repo.byId(id);
      if (row == null || row.status != CaptureStatus.pending) return;
      if (decision == 'confirm') {
        confirm(row);
        confirmed++;
      } else if (decision == 'dismiss') {
        dismiss(row.id);
        dismissed++;
      }
    });

    // Show the captured items immediately, before the (slow, serialized)
    // on-device categorization runs.
    load();
    // Don't re-categorize items already confirmed/dismissed by a decision.
    final pendingNew = newOnes.where((c) => _repo.byId(c.id)?.status == CaptureStatus.pending).toList();
    final categorized = await _categorize(pendingNew, max: maxAiItems);
    load();
    return DrainResult(
      captured: newOnes.length,
      categorized: categorized,
      confirmed: confirmed,
      dismissed: dismissed,
    );
  }

  /// Builds a [CapturedNotification] from a native entry. Known catalog apps are
  /// parsed fully by the Dart parser; discovered (non-catalog) apps fall back to
  /// the native app label + native-parsed amount.
  CapturedNotification? _capturedFromRaw(RawNotification n) {
    final parsed = CaptureParser.parse(package: n.package, title: n.title, text: n.text);
    // Prefer the natively-parsed amount — it's exactly what the confirm
    // notification showed and what the user approved.
    final amount = n.amount ?? parsed?.amount;
    if (parsed == null && amount == null) return null; // unknown app, no money → skip
    // Direction: the Dart parser when it recognized the entity; otherwise the
    // native parse (for discovered apps); default expense only as a last resort.
    final nativeDir = n.direction == 'income' ? EntryType.income : (n.direction == 'expense' ? EntryType.expense : null);
    // Zero-friction category: if we've learned this merchant before, attach the
    // category right away (instant, offline) so even a one-tap confirm files it.
    // Validate against the live catalog so a renamed/deleted category isn't shown.
    final merchant = CaptureParser.extractMerchant(title: n.title, text: n.text);
    var learned = ref.read(merchantMemoryProvider).lookup(merchant)?.name;
    if (learned != null) {
      final cats = ref.read(aiCatalogProvider).categories;
      if (!cats.any((c) => c.name.toLowerCase() == learned!.toLowerCase())) learned = null;
    }
    return CapturedNotification(
      id: n.id,
      package: n.package,
      postedAt: n.postedAt,
      capturedAt: DateTime.now(),
      entityName: parsed?.entity.name ?? n.appName ?? n.package,
      entityType: parsed?.entity.type,
      title: n.title,
      text: n.text,
      amount: amount,
      direction: parsed?.direction ?? nativeDir ?? EntryType.expense,
      cardLast4: parsed?.cardLast4 ?? n.last4,
      suggestedCategory: learned,
      confidence: parsed?.confidence ?? (amount != null ? 0.4 : 0.1),
    );
  }

  /// Runs AI categorization over [items] that have a real amount, bounded by
  /// [max] inference *attempts* so a slow model can't stall on a large backlog.
  ///
  /// Privacy: this only runs with the on-device Gemma client, so the captured
  /// bank text never leaves the phone. With any other provider it is skipped —
  /// the deterministic capture still works and the user picks a category on
  /// confirm. The suggested category is validated against the user's catalog
  /// before being stored, so the inbox only shows real categories.
  Future<int> _categorize(List<CapturedNotification> items, {required int max}) async {
    final ai = ref.read(aiServicesProvider);
    if (ai == null || ai.client is! OnDeviceGemmaClient) return 0;
    final cats = ref.read(aiCatalogProvider).categories.map((c) => c.name).toList();
    if (cats.isEmpty) return 0;
    final catSet = {for (final c in cats) c.toLowerCase()};

    var attempts = 0;
    var categorized = 0;
    for (final c in items) {
      if (attempts >= max) break;
      if (!c.hasAmount) continue;
      if (c.suggestedCategory != null) continue; // already categorized by memory
      attempts++;
      try {
        final s = await ai.categorizeCapture(
          rawText: [c.title, c.text].where((e) => e != null).join('. '),
          merchant: c.title,
          direction: c.direction ?? EntryType.expense,
          categories: cats,
        );
        final cat = s.category;
        if (cat != null && catSet.contains(cat.toLowerCase())) {
          _repo.updateCategory(c.id, cat);
          categorized++;
        }
      } catch (_) {/* leave uncategorized — user can pick a category on confirm */}
    }
    return categorized;
  }

  /// Categorizes the still-pending items on demand (the "Categorizar con IA"
  /// action), for when capture happened before AI was configured.
  Future<int> categorizePending({int max = 15}) async {
    final pending = _repo.pending().where((c) => c.suggestedCategory == null).toList();
    final n = await _categorize(pending, max: max);
    load();
    return n;
  }

  /// Confirms a captured movement into a real transaction. The amount comes from
  /// the deterministic parse (or an [amountOverride] the user typed); the
  /// category from the AI suggestion (or a [categoryOverride]).
  void confirm(
    CapturedNotification c, {
    double? amountOverride,
    String? categoryOverride,
    bool learn = false,
  }) {
    // Only confirm a still-pending capture. Guards against a double-tap or a
    // stale tile tap racing a background decision — both would otherwise mint a
    // second transaction (each gets a fresh tx id, so the upsert won't dedupe).
    final current = _repo.byId(c.id);
    if (current == null || current.status != CaptureStatus.pending) return;

    final amount = amountOverride ?? c.amount;
    if (amount == null || amount <= 0) return; // guarded by the UI

    final categories = ref.read(aiCatalogProvider).categories;
    final accounts = ref.read(aiCatalogProvider).accounts;
    final memory = ref.read(merchantMemoryProvider);
    final merchant = CaptureParser.extractMerchant(title: c.title, text: c.text);

    // Category, in order: the user's explicit pick, the suggestion already on the
    // row (memory or AI), then a fresh memory lookup — then RESOLVED against the
    // live catalog so an orphan (renamed/deleted) name is dropped, not stored.
    final wanted = categoryOverride ?? c.suggestedCategory ?? memory.lookup(merchant)?.name;
    String? categoryName;
    String? categoryId;
    if (wanted != null) {
      final target = wanted.toLowerCase();
      for (final cat in categories) {
        if (cat.name.toLowerCase() == target) {
          categoryName = cat.name; // canonical casing
          categoryId = cat.id;
          break;
        }
      }
    }

    // Match the captured entity to an existing account by name (case-insensitive).
    String accountName = c.entityName ?? 'Efectivo';
    String? accountId;
    final accTarget = accountName.toLowerCase();
    for (final a in accounts) {
      if (a.name.toLowerCase() == accTarget) {
        accountId = a.id;
        accountName = a.name;
        break;
      }
    }

    final note = StringBuffer('Auto-capturado');
    if (c.entityName != null) note.write(' · ${c.entityName}');
    if (c.cardLast4 != null) note.write(' ••${c.cardLast4}');

    // Prefer the parsed merchant as the movement title (e.g. "OXXO") over the
    // generic notification title ("Compra aprobada").
    final title = merchant?.trim().isNotEmpty == true
        ? merchant!.trim()
        : (c.title?.trim().isNotEmpty == true ? c.title!.trim() : (c.entityName ?? 'Movimiento'));

    final entry = FinanceEntry(
      id: newId('tx'),
      title: title,
      amount: amount,
      category: categoryName ?? 'Sin categoría',
      categoryId: categoryId,
      date: c.postedAt,
      type: c.direction ?? EntryType.expense,
      account: accountName,
      accountId: accountId,
      currency: 'MXN',
      note: note.toString(),
      exchangeRate: effectiveMxnRate('MXN'),
      createdAt: DateTime.now(),
    );

    ref.read(transactionsProvider.notifier).add(entry);
    _repo.setStatus(c.id, CaptureStatus.confirmed, transactionId: entry.id);
    // Learn ONLY from an explicit user pick that resolved to a live category —
    // never persist an unvetted AI/auto suggestion into the durable memory.
    if (learn && categoryName != null) {
      memory.learn(merchant, categoryId: categoryId, categoryName: categoryName);
    }
    load();
  }

  void dismiss(String id) {
    _repo.setStatus(id, CaptureStatus.dismissed);
    load();
  }
}

final captureInboxProvider =
    StateNotifierProvider<CaptureInboxNotifier, List<CapturedNotification>>(
        (ref) => CaptureInboxNotifier(ref));

/// Number of pending captured movements (for badges).
final pendingCaptureCountProvider = Provider<int>((ref) => ref.watch(captureInboxProvider).length);
