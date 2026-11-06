import 'game.dart';
import 'screen_time.dart';
import 'storage.dart';
import 'trackers.dart';

/// Uygulamaya bağlı alışkanlık takiplerini (sosyal medya gibi) telefon kullanım verisinden
/// besler: izlenen uygulamaya her giriş bir kayıt olur, sayaç uygulamadan çıkınca yeniden başlar.
class AutoTrack {
  static bool _busy = false;

  /// Yeni açılışları kayıt olarak ekler. Eklenen kayıt sayısını döner.
  static Future<int> sync() async {
    if (_busy || !ScreenTime.supported) return 0;
    final store = Store.instance;
    final auto = [for (final t in store.trackers) if (t.isAuto) t];
    if (auto.isEmpty) return 0;
    _busy = true;
    try {
      if (!await ScreenTime.hasPermission()) return 0;
      final now = DateTime.now();
      var added = 0;
      var dirty = false;

      for (final t in auto) {
        // İlk kez açıldıysa geçmişe dönük kayıt eklenmez; bu andan itibaren izlenir.
        final since = t.autoSync;
        if (since == null) {
          t.autoSync = now;
          dirty = true;
          continue;
        }
        // Yarım kalmış oturumu yakalamak için biraz geriden başla; en çok 7 gün.
        var from = since.subtract(const Duration(minutes: 2));
        final limit = now.subtract(const Duration(days: 7));
        if (from.isBefore(limit)) from = limit;

        final List<AppSession> sessions;
        try {
          sessions = await ScreenTime.sessions(from, now);
        } catch (_) {
          continue;
        }
        for (final s in sessions) {
          if (!_matches(t, s)) continue;
          // Açılış bir kayıt, çıkış sayacın yeni başlangıcı. Önceki eşitlemede
          // görülen (ya da elle silinen) açılışlar tekrar eklenmez.
          if (s.start.isAfter(since) && !t.events.contains(s.start)) {
            t.events.add(s.start);
            added++;
          }
          if (t.autoExit == null || s.end.isAfter(t.autoExit!)) t.autoExit = s.end;
        }
        t.events.sort();
        t.autoSync = now;
        dirty = true;
      }

      if (dirty) {
        await store.saveTrackers();
        Game.instance.changes.value++;
      }
      return added;
    } finally {
      _busy = false;
    }
  }

  static bool _matches(Tracker t, AppSession s) => switch (t.autoMode) {
        AutoMode.off => false,
        AutoMode.social => s.group == AppGroup.social,
        AutoMode.apps => t.autoApps.contains(s.package),
      };
}
