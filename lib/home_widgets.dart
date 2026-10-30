import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'models.dart';
import 'notifications.dart';
import 'pages/item_editor.dart' show itemColors;
import 'storage.dart';
import 'voice_parser.dart';

/// Ana ekran widget'ları (Android): "Bugün" programı ve "Hızlı ekle".
class HomeWidgets {
  static const _todayProvider = 'TodayWidgetProvider';

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// ✅ butonları uygulama kapalıyken de çalışsın diye arka plan işleyicisi.
  static Future<void> init() async {
    if (!supported) return;
    try {
      await HomeWidget.registerInteractivityCallback(homeWidgetCallback);
    } catch (_) {}
  }

  /// Widget'tan açılınca (ör. gunluk://voice) [onUri] çağrılır.
  static Future<void> listen(void Function(Uri uri) onUri) async {
    if (!supported) return;
    try {
      final first = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (first != null) onUri(first);
      HomeWidget.widgetClicked.listen((uri) {
        if (uri != null) onUri(uri);
      });
    } catch (_) {}
  }

  /// Bugünün ve yarının programını widget'a yazar. Yarın da yazılır ki gece yarısından
  /// sonra uygulama açılmadan da widget doğru günü göstersin.
  static Future<void> update() async {
    if (!supported) return;
    try {
      final store = Store.instance;
      final today = dateOnly(DateTime.now());
      Map<String, Object> day(DateTime d) {
        final list = store.items.where((i) => i.occursOn(d)).toList()
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
        return {
          'date': dayKey(d),
          'label': '${d.day} ${trMonths[d.month - 1]} ${trWeekdays[d.weekday - 1]}',
          'items': [
            for (final i in list)
              {
                'id': i.id,
                'start': i.startMinutes,
                'end': i.endMinutes,
                'title': i.title,
                'color': itemColors[i.colorIndex % itemColors.length].toARGB32(),
                'done': store.isDone(i, d),
              },
          ],
        };
      }

      final days = [day(today), day(DateTime(today.year, today.month, today.day + 1))];
      await HomeWidget.saveWidgetData<String>('today_json', jsonEncode(days));
      await HomeWidget.updateWidget(androidName: _todayProvider);
    } catch (_) {}
  }
}

/// Arka plan işleri (uygulama açılmadan):
/// - gunluk://done?id=5&day=2026-10-30 : widget'taki ✅
/// - gunluk://add?text=... : widget'taki 🎙️ ile söylenen komut
@pragma('vm:entry-point')
Future<void> homeWidgetCallback(Uri? uri) async {
  if (uri == null) return;
  if (uri.host == 'add') {
    await _voiceAdd(uri.queryParameters['text'] ?? '');
    return;
  }
  if (uri.host != 'done') return;
  final id = int.tryParse(uri.queryParameters['id'] ?? '');
  if (id == null) return;
  final now = DateTime.now();
  final store = Store.instance;
  // Arka planda ayrı bir Dart ortamı: veriler diskten baştan okunur.
  await store.load(fresh: true);
  // Gece yarısını geçmiş eski bir widget görünümünden gelen dokunuş sayılmaz.
  if (uri.queryParameters['day'] case final d? when d != dayKey(now)) {
    await HomeWidgets.update();
    return;
  }
  final item = store.items.where((i) => i.id == id).firstOrNull;
  if (item == null) return;
  await store.setDone(id, now, !store.isDone(item, now));
  await HomeWidgets.update();
}

/// Söylenen cümleyi uygulamadaki gibi çözer ve kaydeder; sonucu bildirimle söyler.
Future<void> _voiceAdd(String text) async {
  final store = Store.instance;
  await store.load(fresh: true);
  await Notifier.init(handlers: false);
  final cmd = parseVoice(text, store.trackers);
  switch (cmd) {
    case VoiceEvent(:final item):
      final draft = withQuickAlarm(item, quickAlarmBefore);
      final saved = ScheduleItem.fromJson({...draft.toJson(), 'id': store.newId()});
      store.items.add(saved);
      await store.saveItems();
      await Notifier.scheduleItem(saved);
      final d = saved.startDate;
      final today = dateOnly(DateTime.now());
      final when = saved.repeat != Repeat.once
          ? saved.repeatLabel
          : sameDay(d, today)
              ? 'Bugün'
              : sameDay(d, DateTime(today.year, today.month, today.day + 1))
                  ? 'Yarın'
                  : '${d.day} ${trMonths[d.month - 1]}';
      final alarm = saved.alarmMinutesBefore;
      await Notifier.showInfo(
          '✅ ${saved.title} eklendi',
          '$when ${fmtMinutes(saved.startMinutes)}'
              '${alarm == null ? '' : ' · ⏰ ${fmtMinutes((saved.startMinutes - alarm + 1440) % 1440)}'}'
              '\n"$text"');
    case VoiceLog(:final tracker, :final count, :final at):
      for (var i = 0; i < count; i++) {
        tracker.events.add(at.subtract(Duration(seconds: i)));
      }
      tracker.events.sort();
      await store.saveTrackers();
      await Notifier.showInfo('${tracker.emoji} $count ${tracker.unit} kaydedildi',
          '${tracker.name} takibine eklendi\n"$text"');
    case VoiceUnknown(:final message):
      await Notifier.showInfo('🤔 Anlayamadım', '$message\n"$text"');
  }
  await HomeWidgets.update();
}

/// Widget'tan sesle eklenen etkinliğe başlangıçtan kaç dakika önce alarm kurulur.
const quickAlarmBefore = 30;
