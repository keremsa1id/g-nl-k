import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'pages/stats_page.dart';
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

  static const streakGuardId = 900001;
  static const weeklyReportId = 900002;
  static const reportPayload = 'report';

  /// Bildirimden bir etkinlik tamamlanınca artar; sayfalar dinleyip yenilenir.
  static final changes = ValueNotifier<int>(0);

  /// Haftalık rapor bildirimine basınca İstatistikler'i açmak için.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const _infoDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'seri_rapor',
      'Seri ve rapor bildirimleri',
      channelDescription: 'Bozulmak üzere olan seriler ve haftalık rapor',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFE53935),
    ),
  );

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
    if (r.payload == reportPayload) {
      _openReport();
      return;
    }
    final id = int.tryParse(r.payload ?? '');
    if (id == null) return;
    final store = Store.instance;
    final item = store.items.where((i) => i.id == id).firstOrNull;
    if (item == null) return;
    switch (r.actionId) {
      case actionDone:
        await store.setDone(id, DateTime.now(), true);
        changes.value++;
        await refreshExtras();
      case actionSnooze:
        await snooze(item);
    }
  }

  static void _openReport() => navigatorKey.currentState
      ?.push(MaterialPageRoute<void>(builder: (_) => const StatsPage()));

  /// Uygulama haftalık rapor bildirimiyle açıldıysa İstatistikler'e git.
  static Future<void> openFromLaunch() async {
    if (kIsWeb) return;
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp == true &&
        d?.notificationResponse?.payload == reportPayload) {
      _openReport();
    }
  }

  /// 10 dakika sonra aynı etkinlik için tekrar hatırlat.
  static Future<void> snooze(ScheduleItem item) async {
    if (kIsWeb) return;
    final when = tz.TZDateTime.now(tz.local).add(snoozeFor);
    await _schedule(item.id * 10 + 8, 'Ertelendi: ${item.title}',
        '${item.timeLabel} · tekrar hatırlatma', when, null, '${item.id}');
  }

  /// Seri uyarısı ve haftalık raporu güncel verilere göre yeniden kurar.
  static Future<void> refreshExtras() async {
    if (kIsWeb) return;
    await _streakGuard();
    await _weeklyReport();
  }

  /// Saat 21:00'de, o gün henüz yapılmamış ve serisi olan etkinlikler için uyarı.
  static Future<void> _streakGuard() async {
    await _plugin.cancel(streakGuardId);
    final store = Store.instance;
    final now = DateTime.now();
    final today = dateOnly(now);
    final afterNine = now.hour >= 21;
    final day = afterNine ? DateTime(today.year, today.month, today.day + 1) : today;
    final atRisk = <(ScheduleItem, int)>[];
    for (final i in store.items) {
      if (!i.occursOn(day) || store.isDone(i, day)) continue;
      final n = store.streak(i, afterNine ? today : day);
      if (n > 0) atRisk.add((i, n));
    }
    if (atRisk.isEmpty) return;
    atRisk.sort((a, b) => b.$2.compareTo(a.$2));
    final (top, n) = atRisk.first;
    final body = atRisk.length == 1
        ? '${top.title} serin $n — bugün yapmazsan sıfırlanır 🔥'
        : '${atRisk.take(3).map((e) => '${e.$1.title} (${e.$2})').join(', ')} '
            'serilerin bugün bozulmasın 🔥';
    final when = tz.TZDateTime(tz.local, day.year, day.month, day.day, 21);
    await _schedule(streakGuardId, 'Serin tehlikede!', body, when, null, '',
        details: _infoDetails);
  }

  /// Her pazar 20:00'de haftalık rapor hatırlatması.
  static Future<void> _weeklyReport() async {
    await _plugin.cancel(weeklyReportId);
    if (Store.instance.items.isEmpty) return;
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
    while (d.weekday != DateTime.sunday || !d.isAfter(now)) {
      d = tz.TZDateTime(tz.local, d.year, d.month, d.day + 1, 20);
    }
    await _schedule(weeklyReportId, 'Haftalık raporun hazır 📊',
        'Bu hafta neleri tamamladığına ve serilerine göz at', d,
        DateTimeComponents.dayOfWeekAndTime, reportPayload,
        details: _infoDetails);
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
    await refreshExtras();
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
      DateTimeComponents? match, String payload,
      {NotificationDetails details = _details}) async {
    try {
      await _plugin.zonedSchedule(nid, title, body, when, details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: match,
          payload: payload);
    } catch (_) {
      // Tam zamanlı alarm izni yoksa yaklaşık zamanlıya düş.
      await _plugin.zonedSchedule(nid, title, body, when, details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: match,
          payload: payload);
    }
  }
}