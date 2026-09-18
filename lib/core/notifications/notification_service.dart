import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/transactions/domain/currency.dart';
import '../../features/transactions/domain/recurring_transaction.dart';
import '../../features/transactions/domain/transaction.dart';

/// Schedules local reminders for upcoming recurring payments.
///
/// On-device only; no server. Uses inexact scheduling so it does not require
/// the Android 13+ exact-alarm permission. Defaults the timezone to Mexico City
/// for the target audience when the host zone can't be resolved.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'nexo_reminders',
    'Recordatorios',
    channelDescription: 'Avisos de pagos próximos',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
      } catch (_) {/* keep default UTC */}
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService init failed: $e');
    }
  }

  /// Requests OS permission. Returns true if granted (or not required).
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    final iosGranted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return granted ?? iosGranted ?? true;
  }

  /// Cancels existing reminders and schedules one per upcoming payment,
  /// firing at 9:00 on the due date. Returns how many were scheduled.
  static Future<int> scheduleReminders(List<UpcomingPayment> payments) async {
    await init();
    if (!_ready) return 0;
    await _plugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    var id = 1000;
    var scheduled = 0;
    for (final p in payments) {
      final when = tz.TZDateTime(tz.local, p.dueDate.year, p.dueDate.month, p.dueDate.day, 9);
      if (!when.isAfter(now)) continue;
      final verb = p.type == EntryType.income ? 'Cobro' : 'Pago';
      try {
        await _plugin.zonedSchedule(
          id++,
          '$verb próximo: ${p.title}',
          '${formatMoney(p.amount)} · ${p.category}',
          when,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: p.recurringId,
        );
        scheduled++;
      } catch (e) {
        if (kDebugMode) debugPrint('schedule failed: $e');
      }
    }
    return scheduled;
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// Fires an immediate test notification.
  static Future<void> showTest() async {
    await init();
    await _plugin.show(1, 'Nexo', 'Notificaciones activas ✅', _details);
  }
}
