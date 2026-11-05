import 'dart:async';

import 'game.dart';
import 'models.dart';
import 'notifications.dart';
import 'screen_time.dart';
import 'storage.dart';

/// Bir uygulamaya bağlı etkinlikleri telefon kullanım verisine bakıp kendiliğinden
/// tamamlar: o gün bağlı uygulamada etkinlik süresi kadar vakit geçtiyse biter.
class AutoComplete {
  /// Bugün için bekleyen, uygulamaya bağlı etkinlikleri kontrol eder.
  /// Tamamlananları döner (çağıran isterse bildirim/snackbar gösterir).
  static Future<List<ScheduleItem>> checkToday() async {
    if (!ScreenTime.supported) return const [];
    final store = Store.instance;
    final now = DateTime.now();
    final today = dateOnly(now);
    final pending = [
      for (final i in store.items)
        if (i.hasApp && i.occursOn(today) && !store.isDone(i, today)) i,
    ];
    if (pending.isEmpty) return const [];
    if (!await ScreenTime.hasPermission()) return const [];

    final List<AppUsage> usage;
    try {
      usage = await ScreenTime.query(today, now);
    } catch (_) {
      return const [];
    }
    final byPackage = {for (final a in usage) a.package: a.duration};

    final completed = <ScheduleItem>[];
    for (final item in pending) {
      final spent = byPackage[item.appPackage] ?? Duration.zero;
      if (spent >= Duration(minutes: item.durationMinutes)) {
        await store.setDone(item.id, today, true);
        completed.add(item);
      }
    }
    if (completed.isNotEmpty) {
      unawaited(Notifier.refreshExtras());
      Game.instance.changes.value++;
      Notifier.changes.value++;
    }
    return completed;
  }

  /// Bugün [item] için bağlı uygulamada geçen süre (izin yoksa null).
  static Future<Duration?> spentToday(ScheduleItem item) async {
    final pkg = item.appPackage;
    if (pkg == null) return null;
    final now = DateTime.now();
    return ScreenTime.usageOf(pkg, dateOnly(now), now);
  }
}
