import 'dart:typed_data' show Int32List, Int64List;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'categories.dart';
import 'models.dart';
import 'pages/alarm_page.dart';
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
  static const snoozeFor = Duration(minutes: 10);
  static const actionDone = 'done';
  static const actionSnooze = 'snooze';
  static const actionAlarmStop = 'alarm_stop';
  static const actionAlarmSnooze = 'alarm_snooze';
  static const alarmSnoozeFor = Duration(minutes: 5);
  static const alarmPrefix = 'alarm:';

  // Etkinlik bildirim id'leri: item.id * 100 + hatırlatma * 8 + haftanın günü (0..7),
  // ertelenen hatırlatma: item.id * 100 + 99.
  static const _perItem = 100;
  static const _snoozeSlot = 99;
  static const _maxReminders = 12;
  static const streakGuardId = 2000000001;
  static const weeklyReportId = 2000000002;
  static const voiceResultId = 2000000003;
  static const reportPayload = 'report';

  // Alarm id'leri ayrı aralıkta: 1e9 + item.id * 10 + haftanın günü (0..7), ertelenen: +9.
  static const _alarmBase = 1000000000;
  static int _alarmId(ScheduleItem item, int k) => _alarmBase + item.id * 10 + k;

  /// Test alarmı için sahte etkinlik (gerçek id'ler 1'den başlar).
  static const testItemId = 0;
  static ScheduleItem _testItem() {
    final now = DateTime.now();
    return ScheduleItem(
      id: testItemId,
      title: 'Test alarmı',
      startMinutes: now.hour * 60 + now.minute,
      durationMinutes: 30,
      repeat: Repeat.once,
      startDate: dateOnly(now),
      weekdays: const [],
      colorIndex: 0,
      alarmMinutesBefore: 0,
    );
  }

  /// Bildirimden bir etkinlik tamamlanınca artar; sayfalar dinleyip yenilenir.
  static final changes = ValueNotifier<int>(0);

  /// Haftalık rapor bildirimine basınca İstatistikler'i açmak için.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Titreşim deseni (ms): bekle, titre, dur, titre, dur, uzun titre.
  static final _vibration = Int64List.fromList([0, 400, 200, 400, 200, 800]);

  static final _infoDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'seri_rapor_v2',
      'Seri ve rapor bildirimleri',
      channelDescription: 'Bozulmak üzere olan seriler ve haftalık rapor',
      importance: Importance.high,
      priority: Priority.high,
      color: const Color(0xFFE53935),
      enableVibration: true,
      vibrationPattern: _vibration,
    ),
  );

  static final _details = _itemDetails();

  /// [bigText] verilirse bildirim aşağı çekilince çok satırlı görünür (notlar için).
  static NotificationDetails _itemDetails([String? bigText]) => NotificationDetails(
    android: AndroidNotificationDetails(
      'program_hatirlatma_v2',
      'Program hatırlatmaları',
      channelDescription: 'Programdaki etkinlikler için hatırlatmalar',
      importance: Importance.max,
      priority: Priority.high,
      color: const Color(0xFFE53935),
      enableVibration: true,
      vibrationPattern: _vibration,
      playSound: true,
      category: AndroidNotificationCategory.reminder,
      styleInformation: bigText == null ? null : BigTextStyleInformation(bigText),
      actions: const [
        AndroidNotificationAction(actionDone, '✅ Tamamlandı', cancelNotification: true),
        AndroidNotificationAction(actionSnooze, '⏰ 10 dk ertele', cancelNotification: true),
      ],
    ),
  );

  /// Alarm: alarm sesiyle çalar, kapatılana kadar susmaz, kilit ekranında tam ekran açılır.
  static NotificationDetails _alarmDetails(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'alarm_v1',
      'Alarmlar',
      channelDescription: 'Alarm kurulan etkinlikler (sesli, tam ekran)',
      importance: Importance.max,
      priority: Priority.max,
      color: const Color(0xFFE53935),
      playSound: true,
      sound: UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT: kapatılana kadar çalar
      styleInformation: BigTextStyleInformation(body),
      actions: const [
        AndroidNotificationAction(actionAlarmStop, '⏹ Kapat', cancelNotification: true),
        AndroidNotificationAction(actionAlarmSnooze, '😴 5 dk ertele', cancelNotification: true),
        AndroidNotificationAction(actionDone, '✅ Tamamlandı', cancelNotification: true),
      ],
    ),
  );

  /// Alarm bildirimi payload'u: "alarm:<item.id>:<bildirim id>".
  static (int, int)? _parseAlarm(String? payload) {
    if (payload == null || !payload.startsWith(alarmPrefix)) return null;
    final parts = payload.substring(alarmPrefix.length).split(':');
    if (parts.length != 2) return null;
    final id = int.tryParse(parts[0]);
    final nid = int.tryParse(parts[1]);
    return id == null || nid == null ? null : (id, nid);
  }

  /// Bildirim butonları: Tamamlandı -> bugünü işaretle, Ertele -> 10 dk sonra tekrar hatırlat.
  static Future<void> handleResponse(NotificationResponse r) async {
    if (r.payload == reportPayload) {
      _openReport();
      return;
    }
    final alarm = _parseAlarm(r.payload);
    if (alarm != null) {
      await _handleAlarm(r.actionId, alarm.$1, alarm.$2);
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

  static Future<void> _handleAlarm(String? action, int itemId, int nid) async {
    final store = Store.instance;
    final item = itemId == testItemId
        ? _testItem()
        : store.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    switch (action) {
      case actionDone:
        if (itemId == testItemId) return;
        await store.setDone(itemId, DateTime.now(), true);
        changes.value++;
        await refreshExtras();
      case actionAlarmSnooze:
        await snoozeAlarm(item);
      case actionAlarmStop:
        break; // bildirim butonla zaten kapandı
      default:
        // Bildirime basıldı ya da kilit ekranında tam ekran açıldı: alarm ekranını göster.
        navigatorKey.currentState?.push(MaterialPageRoute<void>(
            fullscreenDialog: true, builder: (_) => AlarmPage(item: item, notificationId: nid)));
    }
  }

  /// Uygulama bir bildirimle açıldıysa: rapor -> İstatistikler, alarm -> alarm ekranı.
  static Future<void> openFromLaunch() async {
    if (kIsWeb) return;
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp != true) return;
    final payload = d?.notificationResponse?.payload;
    if (payload == reportPayload) {
      _openReport();
      return;
    }
    final alarm = _parseAlarm(payload);
    if (alarm == null) return;
    // Uygulama sonradan (widget, son uygulamalar) açılınca Android eski alarm intent'ini
    // tekrar verebiliyor: yalnızca alarm bildirimi hâlâ duruyorsa alarm ekranını aç.
    if (!await _isActive(alarm.$2)) return;
    await _handleAlarm(d?.notificationResponse?.actionId, alarm.$1, alarm.$2);
  }

  static Future<bool> _isActive(int nid) async {
    try {
      final a = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (a == null) return true;
      final list = await a.getActiveNotifications();
      return list.any((n) => n.id == nid);
    } catch (_) {
      return true;
    }
  }

  /// Bilgi bildirimi (ör. widget'tan sesle eklenen etkinliğin sonucu).
  static Future<void> showInfo(String title, String body) async {
    if (kIsWeb) return;
    await _plugin.show(voiceResultId, title, body, _infoDetails);
  }

  /// Çalan alarmı susturur. Tekrarlayan alarmın sonraki kurulumu da silindiği için yeniden kurar.
  static Future<void> stopAlarm(ScheduleItem item, int nid) async {
    if (kIsWeb) return;
    await _plugin.cancel(nid);
    await scheduleAlarm(item);
  }

  /// 5 dakika sonra tekrar çal.
  static Future<void> snoozeAlarm(ScheduleItem item) async {
    if (kIsWeb) return;
    final nid = _alarmId(item, 9);
    final when = tz.TZDateTime.now(tz.local).add(alarmSnoozeFor);
    await _scheduleAlarmAt(item, nid, when, null, 'Ertelendi · ${fmtMinutes(item.startMinutes)}');
  }

  /// Alarm kurulan etkinlikler için tam ekran izni (Android 14+ kullanıcıya sorar).
  static Future<void> requestAlarmPermissions() async {
    if (kIsWeb) return;
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (a == null) return;
    final canExact = await a.canScheduleExactNotifications() ?? true;
    if (!canExact) await a.requestExactAlarmsPermission();
    try {
      // Eski eklenti sürümlerinde bu metot yok; varsa çağrılır.
      await (a as dynamic).requestFullScreenIntentPermission();
    } catch (_) {}
  }

  /// [seconds] saniye sonra çalan gerçek bir alarm kurar. Engel varsa nedenini döndürür,
  /// kurulduysa null.
  static Future<String?> testAlarm({int seconds = 15}) async {
    if (kIsWeb) return 'Alarm sadece Android telefonda çalışır.';
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (a == null) return 'Alarm sadece Android telefonda çalışır.';
    if (!(await a.areNotificationsEnabled() ?? true)) {
      await a.requestNotificationsPermission();
      if (!(await a.areNotificationsEnabled() ?? true)) {
        return 'Bildirim izni kapalı. Ayarlar > Uygulamalar > Günlük > Bildirimler\'i aç.';
      }
    }
    await requestAlarmPermissions();
    if (!(await a.canScheduleExactNotifications() ?? true)) {
      return 'Tam zamanlı alarm izni kapalı. Ayarlar > Uygulamalar > Günlük > '
          '"Alarmlar ve hatırlatıcılar" iznini aç.';
    }
    // Kanal daha önce oluştuysa kullanıcı (ya da telefon) sesini kapatmış olabilir.
    try {
      final channels = await a.getNotificationChannels() ?? const [];
      for (final c in channels) {
        if (c.id != 'alarm_v1') continue;
        if (c.importance == Importance.none) {
          return '"Alarmlar" bildirim kanalı kapalı. Ayarlar > Uygulamalar > Günlük > '
              'Bildirimler > Alarmlar\'ı aç.';
        }
        if (!c.playSound || c.importance.value < Importance.high.value) {
          return '"Alarmlar" kanalında ses ya da açılır bildirim kapalı. Ayarlar > Uygulamalar > '
              'Günlük > Bildirimler > Alarmlar\'da sesi ve "ekranda göster"i aç.';
        }
      }
    } catch (_) {}
    final item = _testItem();
    final nid = _alarmId(item, 9);
    await _plugin.cancel(nid);
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    await _scheduleAlarmAt(item, nid, when, null, 'Alarm çalışıyor ✅');
    final pending = await _plugin.pendingNotificationRequests();
    if (!pending.any((p) => p.id == nid)) return 'Alarm kurulamadı (telefon izin vermedi).';
    return null;
  }

  /// Etkinliğin alarmını (varsa) bir sonraki gerçekleşmelere kurar.
  static Future<void> scheduleAlarm(ScheduleItem item) async {
    if (kIsWeb) return;
    for (var k = 0; k <= 7; k++) {
      await _plugin.cancel(_alarmId(item, k));
    }
    final before = item.alarmMinutesBefore;
    if (before == null) return;
    if (item.hasEnd && dateOnly(DateTime.now()).isAfter(dateOnly(item.endDate!))) return;
    final rem = Reminder(before);
    final label = before == 0
        ? 'Saat ${fmtMinutes(item.startMinutes)}'
        : '${fmtDuration(before)} sonra başlıyor (${fmtMinutes(item.startMinutes)})';
    switch (item.repeat) {
      case Repeat.once:
        final when = _nextReminder(item, rem, (d) => sameDay(d, item.startDate));
        if (when != null) await _scheduleAlarmAt(item, _alarmId(item, 0), when, null, label);
      case Repeat.daily:
        final when = _nextReminder(item, rem, (d) => true);
        if (when != null) {
          await _scheduleAlarmAt(item, _alarmId(item, 0), when, DateTimeComponents.time, label);
        }
      case Repeat.weekly:
        for (final wd in item.weekdays) {
          final when = _nextReminder(item, rem, (d) => d.weekday == wd);
          if (when != null) {
            await _scheduleAlarmAt(
                item, _alarmId(item, wd), when, DateTimeComponents.dayOfWeekAndTime, label);
          }
        }
      case Repeat.monthly:
        final when = _nextReminder(item, rem, (d) => d.day == item.startDate.day);
        if (when != null) {
          await _scheduleAlarmAt(
              item, _alarmId(item, 0), when, DateTimeComponents.dayOfMonthAndTime, label);
        }
    }
  }

  static Future<void> _scheduleAlarmAt(ScheduleItem item, int nid, tz.TZDateTime when,
      DateTimeComponents? match, String timing) async {
    final cat = categoryOf(item.category);
    final title = '⏰ ${item.title}${cat == null || cat.name == item.title ? '' : ' · ${cat.name}'}';
    final body = item.note.isEmpty ? timing : '$timing\n📝 ${item.note}';
    final details = _alarmDetails(body);
    final payload = '$alarmPrefix${item.id}:$nid';
    try {
      // alarmClock: Android'in gerçek alarm saati gibi davranır (pil tasarrufunda da çalar).
      await _plugin.zonedSchedule(nid, title, body, when, details,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          matchDateTimeComponents: match,
          payload: payload);
    } catch (_) {
      await _schedule(nid, title, body, when, match, payload, details: details);
    }
  }

  /// 10 dakika sonra aynı etkinlik için tekrar hatırlat.
  static Future<void> snooze(ScheduleItem item) async {
    if (kIsWeb) return;
    final when = tz.TZDateTime.now(tz.local).add(snoozeFor);
    await _schedule(item.id * _perItem + _snoozeSlot, 'Ertelendi: ${item.title}',
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
    // Titreşimsiz eski kanalları kaldır (kanal ayarları sonradan değiştirilemiyor).
    for (final old in ['program_hatirlatma', 'seri_rapor']) {
      try {
        await a.deleteNotificationChannel(old);
      } catch (_) {}
    }
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
    // Ertelenmiş hatırlatmalar korunur, diğerleri yeniden kurulur.
    for (final p in await _plugin.pendingNotificationRequests()) {
      final snoozed = p.id < _alarmBase
          ? p.id % _perItem == _snoozeSlot
          : p.id < streakGuardId && p.id % 10 == 9; // ertelenmiş alarm
      if (!snoozed) await _plugin.cancel(p.id);
    }
    for (final i in items) {
      await scheduleItem(i, cancelFirst: false);
    }
    await refreshExtras();
  }

  static Future<void> cancelItem(ScheduleItem item) async {
    if (kIsWeb) return;
    for (var k = 0; k < _perItem; k++) {
      await _plugin.cancel(item.id * _perItem + k);
    }
    for (var k = 0; k <= 9; k++) {
      await _plugin.cancel(_alarmId(item, k));
    }
  }

  static Future<void> scheduleItem(ScheduleItem item, {bool cancelFirst = true}) async {
    if (kIsWeb) return;
    if (cancelFirst) await cancelItem(item);
    await scheduleAlarm(item);
    // Bitiş tarihi geçmişse bildirim kurma (uygulama her açılışta yeniden planlar).
    if (item.hasEnd && dateOnly(DateTime.now()).isAfter(dateOnly(item.endDate!))) return;

    for (final (r, rem) in item.reminders.take(_maxReminders).indexed) {
      final base = item.id * _perItem + r * 8;
      switch (item.repeat) {
        case Repeat.once:
          final when = _nextReminder(item, rem, (d) => sameDay(d, item.startDate));
          if (when != null) await _zoned(item, rem, base, when, null);
        case Repeat.daily:
          final when = _nextReminder(item, rem, (d) => true);
          if (when != null) await _zoned(item, rem, base, when, DateTimeComponents.time);
        case Repeat.weekly:
          for (final wd in item.weekdays) {
            final when = _nextReminder(item, rem, (d) => d.weekday == wd);
            if (when != null) {
              await _zoned(item, rem, base + wd, when, DateTimeComponents.dayOfWeekAndTime);
            }
          }
        case Repeat.monthly:
          final when = _nextReminder(item, rem, (d) => d.day == item.startDate.day);
          if (when != null) {
            await _zoned(item, rem, base, when, DateTimeComponents.dayOfMonthAndTime);
          }
      }
    }
  }

  /// Etkinliğin bir sonraki gerçekleşmesinden [rem] kadar önceki an.
  static tz.TZDateTime? _nextReminder(
      ScheduleItem item, Reminder rem, bool Function(DateTime) match) {
    final now = tz.TZDateTime.now(tz.local);
    var day = dateOnly(DateTime.now());
    final start = dateOnly(item.startDate);
    if (day.isBefore(start)) day = start;
    for (var i = 0; i < 400; i++) {
      final d = DateTime(day.year, day.month, day.day + i);
      if (!match(d)) continue;
      final event = tz.TZDateTime(tz.local, d.year, d.month, d.day,
          item.startMinutes ~/ 60, item.startMinutes % 60);
      final remind = event.subtract(Duration(minutes: rem.minutesBefore));
      if (remind.isAfter(now)) return remind;
    }
    return null;
  }

  static Future<void> _zoned(ScheduleItem item, Reminder rem, int nid, tz.TZDateTime when,
      DateTimeComponents? match) async {
    final m = rem.minutesBefore;
    final title = m == 0 ? 'Şimdi: ${item.title}' : 'Yaklaşan: ${item.title}';
    final timing = m == 0
        ? 'Başlıyor (${item.timeLabel})'
        : m == 1440
            ? 'Yarın saat ${fmtMinutes(item.startMinutes)}'
            : '${fmtDuration(m)} sonra başlıyor (${item.timeLabel})';
    final body = rem.note.isEmpty ? timing : '📝 ${rem.note}\n$timing';
    await _schedule(nid, title, body, when, match, '${item.id}',
        details: _itemDetails(body));
  }

  static Future<void> _schedule(int nid, String title, String body, tz.TZDateTime when,
      DateTimeComponents? match, String payload,
      {NotificationDetails? details}) async {
    details ??= _details;
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