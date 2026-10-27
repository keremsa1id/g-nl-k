import 'dart:ui' show Color, DartPluginRegistrant;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'storage.dart';

/// Uygulama kapalıyken bildirim butonuna basılınca ayrı bir isolate'te çalışır.
@pragma('vm:entry-point')
Future<void> notificationActionBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  await Store.instance.load();
  await Notifier.init(handlers: false);
  await Notifier.handleResponse(r);
}

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const reminderBefore = Duration(minutes: 5);
  static const snoozeFor = Duration(minutes: 10);
  static const actionDone = 'done';
  static const actionSnooze = 'snooze';

  /// Bildirimden bir etkinlik tamamlanınca artar; sayfalar dinleyip yenilenir.
  static final changes = ValueNotifier<int>(0);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'program_hatirlatma',
      'Program hatırlatmaları',
      channelDescription: 'Programdaki etkinliklerden 5 dakika önce bildirim',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFFE53935),
      actions: [
        AndroidNotificationAction(actionDone, '✅ Tamamlandı', cancelNotification: true),
        AndroidNotificationAction(actionSnooze, '⏰ 10 dk ertele', cancelNotification: true),
      ],
    ),
  );

  /// Bildirim butonları: Tamamlandı -> bugünü işaretle, Ertele -> 10 dk sonra tekrar hatırlat.
  static Future<void> handleResponse(NotificationResponse r) async {
    final id = int.tryParse(r.payload ?? '');
    if (id == null) return;
    final store = Store.instance;
    final item = store.items.where((i) => i.id == id).firstOrNull;
    if (item == null) return;
    switch (r.actionId) {
      case actionDone:
        await store.setDone(id, DateTime.now(), true);
        changes.value++;
      case actionSnooze:
        final when = tz.TZDateTime.now(tz.local).add(snoozeFor);
        await _schedule(item.id * 10 + 8, 'Ertelendi: ${item.title}',
            '${item.timeLabel} · tekrar hatırlatma', when, null, '${item.id}');
    }
  }

  static Future<void> init({bool handlers = true}) async {
    if (kIsWeb) return; // web'de bildirim yok
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    } catch (_) {}
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: handlers ? handleResponse : null,
      onDidReceiveBackgroundNotificationResponse:
          handlers ? notificationActionBackground : null,
    );
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb) return;
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (a == null) return;
    await a.requestNotificationsPermission();
    final canExact = await a.canScheduleExactNotifications() ?? true;
    if (!canExact) await a.requestExactAlarmsPermission();
  }

  static Future<void> showTest() async {
    if (kIsWeb) return;
    await _plugin.show(999999, 'Test bildirimi', 'Bildirimler çalışıyor ✅', _details);
  }

  static Future<void> rescheduleAll(List<ScheduleItem> items) async {
    if (kIsWeb) return;
    // Ertelenmiş hatırlatmalar (id % 10 == 8) korunur, diğerleri yeniden kurulur.
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id % 10 != 8) await _plugin.cancel(p.id);
    }
    for (final i in items) {
      await scheduleItem(i, cancelFirst: false);
    }
  }

  static Future<void> cancelItem(ScheduleItem item) async {
    if (kIsWeb) return;
    for (var k = 0; k <= 8; k++) {
      await _plugin.cancel(item.id * 10 + k);
    }
  }

  static Future<void> scheduleItem(ScheduleItem item, {bool cancelFirst = true}) async {
    if (kIsWeb) return;
    if (cancelFirst) await cancelItem(item);
    if (!item.notify) return;

    switch (item.repeat) {
      case Repeat.once:
        final when = _nextReminder(item, (d) => sameDay(d, item.startDate));
        if (when != null) await _zoned(item, item.id * 10, when, null);
      case Repeat.daily:
        final whenD = _nextReminder(item, (d) => true);
        if (whenD != null) await _zoned(item, item.id * 10, whenD, DateTimeComponents.time);
      case Repeat.weekly:
        for (final wd in item.weekdays) {
          final when = _nextReminder(item, (d) => d.weekday == wd);
          if (when != null) {
            await _zoned(item, item.id * 10 + wd, when, DateTimeComponents.dayOfWeekAndTime);
          }
        }
      case Repeat.monthly:
        final whenM = _nextReminder(item, (d) => d.day == item.startDate.day);
        if (whenM != null) {
          await _zoned(item, item.id * 10, whenM, DateTimeComponents.dayOfMonthAndTime);
        }
    }
  }

  /// Etkinliğin bir sonraki gerçekleşmesinden 5 dk önceki an.
  static tz.TZDateTime? _nextReminder(ScheduleItem item, bool Function(DateTime) match) {
    final now = tz.TZDateTime.now(tz.local);
    var day = dateOnly(DateTime.now());
    final start = dateOnly(item.startDate);
    if (day.isBefore(start)) day = start;
    for (var i = 0; i < 400; i++) {
      final d = DateTime(day.year, day.month, day.day + i);
      if (!match(d)) continue;
      final event = tz.TZDateTime(tz.local, d.year, d.month, d.day,
          item.startMinutes ~/ 60, item.startMinutes % 60);
      final remind = event.subtract(reminderBefore);
      if (remind.isAfter(now)) return remind;
    }
    return null;
  }

  static Future<void> _zoned(ScheduleItem item, int nid, tz.TZDateTime when,
      DateTimeComponents? match) async {
    await _schedule(nid, 'Yaklaşan: ${item.title}',
        '5 dakika sonra başlıyor (${item.timeLabel})', when, match, '${item.id}');
  }

  static Future<void> _schedule(int nid, String title, String body, tz.TZDateTime when,
      DateTimeComponents? match, String payload) async {
    try {
      await _plugin.zonedSchedule(nid, title, body, when, _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: match,
          payload: payload);
    } catch (_) {
      // Tam zamanlı alarm izni yoksa yaklaşık zamanlıya düş.
      await _plugin.zonedSchedule(nid, title, body, when, _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: match,
          payload: payload);
    }
  }
}