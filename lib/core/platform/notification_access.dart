import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A raw notification recorded by the native [NotificationListenerService],
/// before any parsing. Mirrors the map sent across the platform channel.
class RawNotification {
  RawNotification({
    required this.id,
    required this.package,
    required this.postedAt,
    this.appName,
    this.title,
    this.text,
    this.key,
    this.amount,
    this.last4,
    this.direction,
  });

  /// Stable id assigned natively (used for dedup and to match Sí/No decisions).
  final String id;
  final String package;
  final DateTime postedAt;

  /// The source app's display label (from PackageManager) — used as the account
  /// name for discovered (non-catalog) apps.
  final String? appName;
  final String? title;
  final String? text;

  /// The Android StatusBarNotification key (stable per notification instance).
  final String? key;

  /// Amount parsed natively (what the confirm notification showed). The Dart
  /// parser is authoritative for known entities, but this is preferred when set.
  final double? amount;
  final String? last4;

  /// Direction parsed natively ('income' | 'expense'), used for discovered apps
  /// the Dart catalog parser doesn't recognize.
  final String? direction;

  static RawNotification fromMap(Map<dynamic, dynamic> m) {
    final ms = (m['postedAt'] as num?)?.toInt() ?? 0;
    return RawNotification(
      id: (m['id'] as String?) ?? '',
      package: (m['package'] as String?) ?? '',
      postedAt: DateTime.fromMillisecondsSinceEpoch(ms),
      appName: m['appName'] as String?,
      title: m['title'] as String?,
      text: m['text'] as String?,
      key: m['key'] as String?,
      amount: (m['amount'] as num?)?.toDouble(),
      last4: m['last4'] as String?,
      direction: m['direction'] as String?,
    );
  }
}

/// Result of draining the native buffer: new captures + Sí/No decisions taken
/// from the confirm notification (which may target already-drained captures).
class DrainPayload {
  DrainPayload({required this.entries, required this.decisions});
  final List<RawNotification> entries;

  /// captureId → 'confirm' | 'dismiss'.
  final Map<String, String> decisions;

  static const empty = DrainPayload._empty();
  const DrainPayload._empty()
      : entries = const [],
        decisions = const {};
}

/// Dart side of the Android NotificationListenerService bridge.
///
/// The native service records notifications from allowlisted finance apps into
/// a persistent buffer even while the app is closed. The app drains that buffer
/// on the main isolate (where the AI/Gemma client lives) to parse and review
/// them. All methods are no-ops / safe defaults off Android.
class NotificationAccess {
  NotificationAccess._();

  static const MethodChannel _channel = MethodChannel('nexo/notification_capture');

  /// AutoCapture is Android-only — iOS cannot read other apps' notifications.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Whether notification-listener access has been granted in system settings.
  static Future<bool> isAccessGranted() async {
    if (!isSupported) return false;
    try {
      return (await _channel.invokeMethod<bool>('isGranted')) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system "Notification access" settings so the user can toggle Nexo.
  static Future<void> openAccessSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // ignore — UI shows a fallback hint
    } on MissingPluginException {
      // ignore
    }
  }

  /// Asks the framework to rebind the listener service. Notification-listener
  /// bindings are fragile (app updates, OEM battery kills can tear them down and
  /// not auto-rebind), so call this when access is granted / on app foreground.
  static Future<void> requestRebind() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('requestRebind');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// Tells the native listener which packages to record (the user's enabled
  /// allowlist). An empty list disables capture entirely.
  static Future<void> setAllowlist(List<String> packages) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setAllowlist', {'packages': packages});
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// Pushes the discovery / confirm-notification flags to the native listener.
  static Future<void> setFlags({required bool discovery, required bool confirmNotify}) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setFlags', {
        'discovery': discovery,
        'confirmNotify': confirmNotify,
      });
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// Returns and clears the buffered notifications + the Sí/No decisions taken
  /// from the confirm notification since the last drain.
  static Future<DrainPayload> drain() async {
    if (!isSupported) return DrainPayload.empty;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('drain');
      if (res == null) return DrainPayload.empty;
      final rawEntries = (res['entries'] as List?) ?? const [];
      final entries = rawEntries
          .whereType<Map>()
          .map((m) => RawNotification.fromMap(m))
          .where((n) => n.package.isNotEmpty && n.id.isNotEmpty)
          .toList();
      final rawDecisions = (res['decisions'] as Map?) ?? const {};
      final decisions = <String, String>{
        for (final e in rawDecisions.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      };
      return DrainPayload(entries: entries, decisions: decisions);
    } on PlatformException {
      return DrainPayload.empty;
    } on MissingPluginException {
      return DrainPayload.empty;
    }
  }
}
