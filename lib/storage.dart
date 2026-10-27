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
