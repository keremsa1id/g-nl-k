import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const reminderBefore = Duration(minutes: 5);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'program_hatirlatma',
      'Program hatırlatmaları',
      channelDescription: 'Programdaki etkinliklerden 5 dakika önce bildirim',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    if (kIsWeb) return; // web'de bildirim yok
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    } catch (_) {}
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
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
    await _plugin.cancelAll();
    for (final i in items) {
      await scheduleItem(i, cancelFirst: false);
    }
  }

  static Future<void> cancelItem(ScheduleItem item) async {
    if (kIsWeb) return;
    for (var k = 0; k <= 7; k++) {
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
    final title = 'Yaklaşan: ${item.title}';
    final body = '5 dakika sonra başlıyor (${item.timeLabel})';
    try {
      await _plugin.zonedSchedule(nid, title, body, when, _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: match);
    } catch (_) {
      // Tam zamanlı alarm izni yoksa yaklaşık zamanlıya düş.
      await _plugin.zonedSchedule(nid, title, body, when, _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: match);
    }
  }
}