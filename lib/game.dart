import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'storage.dart';
import 'trackers.dart';

// ---------- Kurallar ----------

const xpPerDone = 20; // programdaki bir etkinliği tamamlamak
const xpPerEvent = -15; // takipteki her kayıt (sigara içmek, alkol…)
const dailyGameXpCap = 100; // mini oyunlardan günde en fazla

/// [level] seviyesinden bir sonrakine geçmek için gereken XP.
int xpToNext(int level) => 100 + (level - 1) * 50;

/// Toplam XP'ye göre (seviye, seviyedeki XP, sonraki seviyeye gereken).
(int, int, int) levelFor(int xp) {
  var level = 1;
  var left = max(0, xp);
  while (left >= xpToNext(level)) {
    left -= xpToNext(level);
    level++;
  }
  return (level, left, xpToNext(level));
}

const _titles = [
  (1, '🌱', 'Acemi'),
  (3, '🌿', 'Çırak'),
  (5, '🔥', 'Kararlı'),
  (8, '⚡', 'Disiplinli'),
  (12, '🛡️', 'İrade Sahibi'),
  (17, '🏆', 'Usta'),
  (25, '👑', 'Efsane'),
];

/// Seviyenin unvanı: (emoji, ad).
(String, String) titleFor(int level) {
  var t = _titles.first;
  for (final x in _titles) {
    if (level >= x.$1) t = x;
  }
  return (t.$2, t.$3);
}

// ---------- Profil ----------

const genders = ['Erkek', 'Kadın', 'Belirtmek istemiyorum'];
const activityLevels = [
  ('Hareketsiz', 'Masa başı, spor yok', 1.2),
  ('Az hareketli', 'Haftada 1-3 gün spor', 1.375),
  ('Orta', 'Haftada 3-5 gün spor', 1.55),
  ('Çok hareketli', 'Haftada 6-7 gün spor', 1.725),
];

class Profile {
  String name = '';
  int? birthYear;
  int? gender; // genders içindeki sıra
  double? heightCm;
  double? weightKg;
  double? goalWeightKg;
  int activity = 1;
  int wakeMinutes = 7 * 60;
  int bedMinutes = 23 * 60;
  final List<(DateTime, double)> weights = []; // kilo geçmişi, sıralı

  int? get age => birthYear == null ? null : DateTime.now().year - birthYear!;

  double? get bmi => heightCm == null || weightKg == null || heightCm! <= 0
      ? null
      : weightKg! / pow(heightCm! / 100, 2);

  /// Mifflin-St Jeor ile bazal metabolizma (kcal/gün).
  double? get bmr {
    if (heightCm == null || weightKg == null || age == null) return null;
    final base = 10 * weightKg! + 6.25 * heightCm! - 5 * age!;
    return switch (gender) { 0 => base + 5, 1 => base - 161, _ => base - 78 };
  }

  /// Günlük kalori ihtiyacı (aktiviteye göre).
  double? get tdee => bmr == null ? null : bmr! * activityLevels[activity].$3;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (birthYear != null) 'birthYear': birthYear,
        if (gender != null) 'gender': gender,
        if (heightCm != null) 'height': heightCm,
        if (weightKg != null) 'weight': weightKg,
        if (goalWeightKg != null) 'goal': goalWeightKg,
        'activity': activity,
        'wake': wakeMinutes,
        'bed': bedMinutes,
        'weights': [for (final (d, w) in weights) [d.toIso8601String(), w]],
      };

  static Profile fromJson(Map<String, dynamic> j) {
    final p = Profile()
      ..name = (j['name'] as String?) ?? ''
      ..birthYear = j['birthYear'] as int?
      ..gender = j['gender'] as int?
      ..heightCm = (j['height'] as num?)?.toDouble()
      ..weightKg = (j['weight'] as num?)?.toDouble()
      ..goalWeightKg = (j['goal'] as num?)?.toDouble()
      ..activity = ((j['activity'] as int?) ?? 1).clamp(0, activityLevels.length - 1)
      ..wakeMinutes = (j['wake'] as int?) ?? 7 * 60
      ..bedMinutes = (j['bed'] as int?) ?? 23 * 60;
    for (final e in (j['weights'] as List<dynamic>?) ?? []) {
      final l = e as List<dynamic>;
      p.weights.add((DateTime.parse(l[0] as String), (l[1] as num).toDouble()));
    }
    return p;
  }
}

// ---------- XP kayıtları ----------

/// Görev ödülü, mini oyun gibi elle verilen XP.
class XpEntry {
  const XpEntry(this.time, this.amount, this.reason, this.kind);

  final DateTime time;
  final int amount;
  final String reason;
  final String kind; // 'quest' | 'game'

  Map<String, dynamic> toJson() =>
      {'t': time.toIso8601String(), 'a': amount, 'r': reason, 'k': kind};

  factory XpEntry.fromJson(Map<String, dynamic> j) => XpEntry(
      DateTime.parse(j['t'] as String), j['a'] as int, j['r'] as String, j['k'] as String);
}

// ---------- Görevler ----------

enum QuestState { active, done, failed }

class Quest {
  const Quest(this.id, this.emoji, this.title, this.hint, this.xp, this.check);

  final String id;
  final String emoji;
  final String title;
  final String hint; // görevin ayrıntısı / ne zaman biteceği
  final int xp;

  /// (gün, şimdi) → durum. Geçmiş günler için şimdi = günün bitişi.
  final QuestState Function(DateTime day, DateTime now) check;
}

/// Oyun katmanı: profil, XP, seviye, günlük görevler, mini oyunlar.
class Game {
  Game._();
  static final Game instance = Game._();

  late SharedPreferences _p;
  final store = Store.instance;

  Profile profile = Profile();
  List<XpEntry> log = [];
  Set<String> claimed = {}; // "gün:görevId"
  late DateTime start; // XP bu tarihten itibaren sayılır

  /// Profil / XP değişince artar.
  final changes = ValueNotifier<int>(0);

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    try {
      profile = Profile.fromJson(
          jsonDecode(_p.getString('profile') ?? '{}') as Map<String, dynamic>);
    } catch (_) {
      profile = Profile();
    }
    try {
      log = (jsonDecode(_p.getString('xpLog') ?? '[]') as List<dynamic>)
          .map((e) => XpEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      log = [];
    }
    claimed = (_p.getStringList('claimed') ?? []).toSet();
    // Eski kayıtlar (ör. aylarca sigara) XP'yi eksiye çekmesin diye sayım bugünden başlar.
    final s = DateTime.tryParse(_p.getString('gameStart') ?? '');
    if (s == null) {
      start = dateOnly(DateTime.now());
      await _p.setString('gameStart', start.toIso8601String());
    } else {
      start = s;
    }
  }

  Future<void> saveProfile() async {
    await _p.setString('profile', jsonEncode(profile.toJson()));
    changes.value++;
  }

  /// Yeni kilo kaydı; aynı gün tekrar girilirse günceller.
  Future<void> logWeight(double kg) async {
    final today = dateOnly(DateTime.now());
    profile.weights.removeWhere((e) => sameDay(e.$1, today));
    profile.weights.add((today, kg));
    profile.weights.sort((a, b) => a.$1.compareTo(b.$1));
    profile.weightKg = kg;
    await saveProfile();
  }

  Future<void> _saveLog() async {
    await _p.setString('xpLog', jsonEncode(log.map((e) => e.toJson()).toList()));
    await _p.setStringList('claimed', claimed.toList());
    changes.value++;
  }

  // ---------- XP hesabı ----------

  String get _startKey => dayKey(start);

  /// Başlangıçtan beri tamamlanan etkinlik sayısı.
  int get doneCount {
    var n = 0;
    for (final days in store.done.values) {
      n += days.where((k) => k.compareTo(_startKey) >= 0).length;
    }
    return n;
  }

  /// Başlangıçtan beri takiplerdeki kayıt sayısı (sigara vb.).
  int get eventCount {
    var n = 0;
    for (final t in store.trackers) {
      n += t.events.where((e) => !e.isBefore(start)).length;
    }
    return n;
  }

  int get questXp => log.where((e) => e.kind == 'quest').fold(0, (a, e) => a + e.amount);
  int get gameXp => log.where((e) => e.kind == 'game').fold(0, (a, e) => a + e.amount);

  /// Ham toplam (eksi olabilir); seviye hesabında 0'ın altı 0 sayılır.
  int get totalXp => doneCount * xpPerDone + eventCount * xpPerEvent + questXp + gameXp;

  /// Bir günde kazanılan / kaybedilen XP.
  int xpOn(DateTime day) {
    final k = dayKey(day);
    if (k.compareTo(_startKey) < 0) return 0;
    var xp = 0;
    for (final days in store.done.values) {
      if (days.contains(k)) xp += xpPerDone;
    }
    for (final t in store.trackers) {
      xp += t.countOn(day) * xpPerEvent;
    }
    for (final e in log) {
      if (sameDay(e.time, day)) xp += e.amount;
    }
    return xp;
  }

  int gameXpOn(DateTime day) =>
      log.where((e) => e.kind == 'game' && sameDay(e.time, day)).fold(0, (a, e) => a + e.amount);

  /// Mini oyun ödülü; günlük sınırı aşmayacak kadarını verir, verileni döndürür.
  Future<int> awardGame(String game, int xp) async {
    final left = dailyGameXpCap - gameXpOn(DateTime.now());
    final given = xp.clamp(0, max(0, left));
    // Ödül sıfır olsa da oyun kaydı tutulur ("bir mini oyun oyna" görevi için).
    log.add(XpEntry(DateTime.now(), given, game, 'game'));
    await _saveLog();
    return given;
  }

  // ---------- Görevler ----------

  DateTime _at(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));

  /// Yatma saati; gece yarısından sonraysa (ör. 01:00) ertesi güne sayılır.
  int get _bed => profile.bedMinutes < 4 * 60 ? profile.bedMinutes + 24 * 60 : profile.bedMinutes;

  /// Gün ne zaman "bitti" sayılır: yatma saati.
  DateTime dayClose(DateTime day) => _at(day, _bed);

  /// Geçmiş bir gün için "şimdi" = günün sonu; bugün için gerçek an.
  DateTime _nowFor(DateTime day) {
    final now = DateTime.now();
    final close = dayClose(day);
    final dayEnd = _at(day, 24 * 60);
    final end = close.isAfter(dayEnd) ? close : dayEnd;
    return now.isAfter(end) ? end.add(const Duration(seconds: 1)) : now;
  }

  /// [from, to) aralığında kayıt yoksa: bitince done, kayıt varsa failed.
  QuestState _noneBetween(Tracker t, DateTime from, DateTime to, DateTime now) {
    if (t.events.any((e) => !e.isBefore(from) && e.isBefore(to))) return QuestState.failed;
    return now.isBefore(to) ? QuestState.active : QuestState.done;
  }

  List<Quest> _trackerQuests(Tracker t, DateTime day) {
    final n = t.name;
    final u = t.unit;
    final bed = _bed;
    final wake = profile.wakeMinutes;
    final close = dayClose(day);
    final dayEvents = t.events.where((e) => sameDay(e, day)).toList();

    // Son 7 günün ortalaması (limit görevi için).
    var week = 0;
    for (var i = 1; i <= 7; i++) {
      week += t.countOn(DateTime(day.year, day.month, day.day - i));
    }
    final limit = (week / 7 * 0.8).floor();

    return [
      Quest('noon_${t.id}', '☀️', 'Öğleden önce ${n.toLowerCase()} yok',
          'Saat 12:00\'ye kadar hiç kayıt girme', 40,
          (d, now) => _noneBetween(t, _at(d, 4 * 60), _at(d, 12 * 60), now)),
      Quest('bed_${t.id}', '🌙', 'Yatmadan 2 saat önce ${n.toLowerCase()} yok',
          '${fmtMinutes(bed - 120)} – ${fmtMinutes(bed)} arası temiz kal', 40,
          (d, now) => _noneBetween(t, _at(d, bed - 120), _at(d, bed), now)),
      Quest('wake_${t.id}', '⏰', 'Uyanınca ilk 2 saat ${n.toLowerCase()} yok',
          '${fmtMinutes(wake)} – ${fmtMinutes(wake + 120)} arası', 30,
          (d, now) => _noneBetween(t, _at(d, wake), _at(d, wake + 120), now)),
      Quest('gap_${t.id}', '⏳', 'İki $u arası en az 2 saat',
          'Gün boyu kayıtlar arasında 2 saatten az olmasın', 35, (d, now) {
        for (var i = 1; i < dayEvents.length; i++) {
          if (dayEvents[i].difference(dayEvents[i - 1]).inMinutes < 120) {
            return QuestState.failed;
          }
        }
        return now.isBefore(close) ? QuestState.active : QuestState.done;
      }),
      if (week > 0)
        Quest('limit_${t.id}', '📉', limit == 0 ? 'Bugün hiç $u yok' : 'Bugün en fazla $limit $u',
            'Son 7 günün ortalamasından %20 az', 45, (d, now) {
          if (dayEvents.length > limit) return QuestState.failed;
          return now.isBefore(close) ? QuestState.active : QuestState.done;
        }),
      Quest('clean_${t.id}', '🏅', 'Bütün gün ${n.toLowerCase()} yok', 'Tam temiz bir gün', 80,
          (d, now) => _noneBetween(t, _at(d, 0), close, now)),
    ];
  }

  List<Quest> _generalQuests(DateTime day) {
    final items = store.items.where((i) => i.occursOn(day)).toList();
    int doneOn(DateTime d) => items.where((i) => store.isDone(i, d)).length;
    QuestState byEnd(bool ok, DateTime d, DateTime now) =>
        ok ? QuestState.done : (now.isBefore(dayClose(d)) ? QuestState.active : QuestState.failed);
    const sportCats = {0, 7, 10, 11, 12, 13};
    final sport = items.where((i) => sportCats.contains(i.category)).toList();

    return [
      if (items.length >= 2)
        Quest('done2', '✅', '2 etkinliği tamamla', 'Programındaki herhangi 2 etkinlik', 30,
            (d, now) => byEnd(doneOn(d) >= 2, d, now)),
      if (items.length >= 3)
        Quest('doneall', '🎯', 'Bugünkü tüm etkinlikleri bitir',
            '${items.length} etkinliğin hepsi', 60,
            (d, now) => byEnd(doneOn(d) >= items.length, d, now)),
      if (sport.isNotEmpty)
        Quest('sport', '💪', 'Bir spor etkinliğini tamamla', sport.first.title, 35,
            (d, now) => byEnd(sport.any((i) => store.isDone(i, d)), d, now)),
      Quest('journal', '📝', 'Günlüğüne birkaç satır yaz', 'Program sayfasının en altında', 25,
          (d, now) =>
              byEnd(!(store.journalFor(d)?.isEmpty ?? true), d, now)),
      Quest('game', '🎮', 'Bir mini oyun oyna', 'Profil sayfasındaki oyunlardan biri', 20,
          (d, now) => byEnd(log.any((e) => e.kind == 'game' && sameDay(e.time, d)), d, now)),
    ];
  }

  /// Günün görevleri: takip varsa 2 takip görevi + 2 genel görev (gün içinde sabit).
  List<Quest> questsFor(DateTime day) {
    final seed = day.year * 10000 + day.month * 100 + day.day;
    final rnd = Random(seed);
    final tracker = [for (final t in store.trackers) ..._trackerQuests(t, day)]..shuffle(rnd);
    final general = _generalQuests(day)..shuffle(Random(seed + 1));
    final want = tracker.isEmpty ? 4 : 2;
    return [...tracker.take(2), ...general.take(want)];
  }

  QuestState stateOf(Quest q, DateTime day) => q.check(day, _nowFor(day));

  bool isClaimed(Quest q, DateTime day) => claimed.contains('${dayKey(day)}:${q.id}');

  Future<void> claim(Quest q, DateTime day) async {
    if (isClaimed(q, day) || stateOf(q, day) != QuestState.done) return;
    claimed.add('${dayKey(day)}:${q.id}');
    log.add(XpEntry(DateTime.now(), q.xp, q.title, 'quest'));
    await _saveLog();
  }

  /// Ödülü alınmamış, tamamlanmış görev sayısı (bugün + dün).
  int get unclaimedCount {
    final today = dateOnly(DateTime.now());
    final y = DateTime(today.year, today.month, today.day - 1);
    var n = 0;
    for (final d in [today, y]) {
      if (d.isBefore(start)) continue;
      for (final q in questsFor(d)) {
        if (!isClaimed(q, d) && stateOf(q, d) == QuestState.done) n++;
      }
    }
    return n;
  }
}
