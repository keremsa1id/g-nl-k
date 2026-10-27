import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Tüm veriler telefonda (SharedPreferences) JSON olarak saklanır.
class Store {
  Store._();
  static final Store instance = Store._();

  late SharedPreferences _p;

  List<ScheduleItem> items = [];
  List<DateTime> smokes = [];
  List<PackPurchase> packs = [];
  DateTime? quitStart; // sigara kaydı olmadan sayacı başlatmak için
  Map<int, Set<String>> done = {}; // etkinlik id -> tamamlandığı günler (dayKey)
  int _nextId = 1;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    _nextId = _p.getInt('nextId') ?? 1;
    items = _decode(_p.getString('items'))
        .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
        .toList();
    smokes = _decode(_p.getString('smokes'))
        .map((e) => DateTime.parse(e as String))
        .toList()
      ..sort();
    packs = _decode(_p.getString('packs'))
        .map((e) => PackPurchase.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final q = _p.getString('quitStart');
    quitStart = q == null ? null : DateTime.tryParse(q);
    _loadDone();
  }

  /// Bildirimden (arka planda) yapılan değişiklikleri okumak için.
  Future<void> reloadDone() async {
    await _p.reload();
    _loadDone();
  }

  void _loadDone() {
    done = {};
    try {
      final m = jsonDecode(_p.getString('done') ?? '{}') as Map<String, dynamic>;
      m.forEach((k, v) => done[int.parse(k)] = (v as List<dynamic>).cast<String>().toSet());
    } catch (_) {}
  }

  Future<void> saveDone() => _p.setString(
      'done', jsonEncode(done.map((k, v) => MapEntry('$k', v.toList()..sort()))));

  bool isDone(ScheduleItem item, DateTime day) =>
      done[item.id]?.contains(dayKey(day)) ?? false;

  Future<void> setDone(int itemId, DateTime day, bool value) async {
    final set = done.putIfAbsent(itemId, () => {});
    value ? set.add(dayKey(day)) : set.remove(dayKey(day));
    if (set.isEmpty) done.remove(itemId);
    await saveDone();
  }

  /// Başlangıçtan bugüne kadarki en uzun seri.
  int bestStreak(ScheduleItem item) {
    final days = done[item.id];
    if (days == null || days.isEmpty) return 0;
    final today = dateOnly(DateTime.now());
    var d = dateOnly(item.startDate);
    final limit = DateTime(today.year, today.month, today.day - 1100);
    if (d.isBefore(limit)) d = limit;
    var run = 0, best = 0;
    while (!d.isAfter(today)) {
      if (item.occursOn(d)) {
        if (days.contains(dayKey(d))) {
          run++;
          if (run > best) best = run;
        } else if (!sameDay(d, today)) {
          run = 0;
        }
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return best;
  }

  /// [from]..[to] arasında (bugünü geçmeden) tamamlanan ve planlanan gerçekleşme sayısı.
  (int, int) tally(ScheduleItem item, DateTime from, DateTime to) {
    final today = dateOnly(DateTime.now());
    final end = to.isAfter(today) ? today : dateOnly(to);
    final start = dateOnly(item.startDate);
    var d = dateOnly(from);
    if (d.isBefore(start)) d = start;
    var n = 0, total = 0;
    while (!d.isAfter(end)) {
      if (item.occursOn(d)) {
        total++;
        if (isDone(item, d)) n++;
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return (n, total);
  }

  /// [asOf] gününe kadar art arda tamamlanan gerçekleşme sayısı.
  /// [asOf] henüz tamamlanmadıysa seriyi bozmaz, bir öncekinden sayılır.
  int streak(ScheduleItem item, DateTime asOf) {
    final days = done[item.id];
    if (days == null || days.isEmpty) return 0;
    final start = dateOnly(item.startDate);
    var count = 0;
    for (var i = 0; i < 1000; i++) {
      final d = DateTime(asOf.year, asOf.month, asOf.day - i);
      if (d.isBefore(start)) break;
      if (!item.occursOn(d)) continue;
      if (days.contains(dayKey(d))) {
        count++;
      } else if (i > 0) {
        break;
      }
    }
    return count;
  }

  static List<dynamic> _decode(String? s) {
    if (s == null) return [];
    try {
      return jsonDecode(s) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  int newId() {
    final id = _nextId++;
    _p.setInt('nextId', _nextId);
    return id;
  }

  Future<void> saveItems() =>
      _p.setString('items', jsonEncode(items.map((e) => e.toJson()).toList()));

  Future<void> saveSmoking() async {
    await _p.setString(
        'smokes', jsonEncode(smokes.map((e) => e.toIso8601String()).toList()));
    await _p.setString('packs', jsonEncode(packs.map((e) => e.toJson()).toList()));
    if (quitStart == null) {
      await _p.remove('quitStart');
    } else {
      await _p.setString('quitStart', quitStart!.toIso8601String());
    }
  }

  /// Sayacın başladığı an: son sigara veya manuel başlangıç (hangisi sonraysa).
  DateTime? get counterStart {
    final last = smokes.isEmpty ? null : smokes.last;
    if (last == null) return quitStart;
    if (quitStart == null) return last;
    return last.isAfter(quitStart!) ? last : quitStart;
  }
}
