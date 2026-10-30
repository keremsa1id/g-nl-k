import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:health/health.dart';

import 'models.dart';

/// Bir günün sağlık verisi (Health Connect).
class DayHealth {
  int? steps;
  Duration? sleep; // o sabah biten gecenin uykusu
  DateTime? sleepStart;
  DateTime? sleepEnd;
  final List<Workout> workouts = [];
}

class Workout {
  const Workout(this.name, this.start, this.duration);

  final String name;
  final DateTime start;
  final Duration duration;
}

enum HealthStatus { unsupported, notInstalled, needsUpdate, ready }

/// Android Health Connect'ten adım, uyku ve egzersiz okur; telefonun ya da
/// bağlı saatin / bilekliğin yazdığı veriler de gelir.
class HealthData {
  HealthData._();
  static final HealthData instance = HealthData._();

  final _health = Health();
  bool _configured = false;

  /// İzin verildi mi (son kontrol).
  bool connected = false;

  /// dayKey -> o günün verisi.
  final Map<String, DayHealth> days = {};
  String? _historyFor;
  DateTime? _lastToday;
  bool _busy = false;

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];
  static final _read = [for (final _ in _types) HealthDataAccess.READ];

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthStatus> status() async {
    if (!supported) return HealthStatus.unsupported;
    try {
      await _configure();
      final s = await _health.getHealthConnectSdkStatus();
      return switch (s) {
        HealthConnectSdkStatus.sdkAvailable => HealthStatus.ready,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => HealthStatus.needsUpdate,
        _ => HealthStatus.notInstalled,
      };
    } catch (_) {
      return HealthStatus.notInstalled;
    }
  }

  /// Play Store'da Health Connect sayfasını açar.
  Future<void> install() async {
    try {
      await _configure();
      await _health.installHealthConnect();
    } catch (_) {}
  }

  Future<bool> checkConnected() async {
    if (!supported) return connected = false;
    try {
      await _configure();
      connected = await _health.hasPermissions(_types, permissions: _read) ?? false;
    } catch (_) {
      connected = false;
    }
    return connected;
  }

  /// Health Connect izin ekranını açar.
  Future<bool> connect() async {
    if (!supported) return false;
    try {
      await _configure();
      await _health.requestAuthorization(_types, permissions: _read);
    } catch (_) {}
    final ok = await checkConnected();
    if (ok) await refresh(force: true);
    return ok;
  }

  DayHealth? day(DateTime d) => days[dayKey(d)];

  DayHealth _slot(DateTime d) => days.putIfAbsent(dayKey(d), DayHealth.new);

  /// Bugünü (en fazla 2 dakikada bir), geçmiş 30 günü günde bir kez okur.
  Future<void> refresh({bool force = false}) async {
    if (!supported || _busy) return;
    final now = DateTime.now();
    if (!force && _lastToday != null && now.difference(_lastToday!).inMinutes < 2) return;
    _busy = true;
    try {
      if (!await checkConnected()) return;
      final today = dateOnly(now);
      if (force || _historyFor != dayKey(today)) {
        for (var i = 1; i <= 30; i++) {
          await _loadSteps(DateTime(today.year, today.month, today.day - i));
        }
        for (var i = 1; i <= 14; i++) {
          await _loadSleep(DateTime(today.year, today.month, today.day - i));
        }
        await _loadWorkouts(DateTime(today.year, today.month, today.day - 14), now);
        _historyFor = dayKey(today);
      }
      await _loadSteps(today);
      await _loadSleep(today);
      await _loadWorkouts(today, now);
      _lastToday = now;
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadSteps(DateTime d) async {
    try {
      final end = DateTime(d.year, d.month, d.day + 1);
      final now = DateTime.now();
      _slot(d).steps =
          await _health.getTotalStepsInInterval(d, end.isAfter(now) ? now : end) ?? 0;
    } catch (_) {}
  }

  /// [d] sabahı biten gece: önceki gün 18:00 – o gün 14:00 arasındaki uyku.
  Future<void> _loadSleep(DateTime d) async {
    try {
      final from = DateTime(d.year, d.month, d.day - 1, 18);
      final to = DateTime(d.year, d.month, d.day, 14);
      final points = await _health.getHealthDataFromTypes(
          types: const [HealthDataType.SLEEP_SESSION], startTime: from, endTime: to);
      final seen = <String>{};
      var total = Duration.zero;
      DateTime? start, end;
      for (final p in points) {
        // Aynı oturumu farklı kaynaklar yazmış olabilir.
        if (!seen.add('${p.dateFrom.millisecondsSinceEpoch}-${p.dateTo.millisecondsSinceEpoch}')) {
          continue;
        }
        total += p.dateTo.difference(p.dateFrom);
        if (start == null || p.dateFrom.isBefore(start)) start = p.dateFrom;
        if (end == null || p.dateTo.isAfter(end)) end = p.dateTo;
      }
      final slot = _slot(d);
      slot.sleep = total == Duration.zero ? null : total;
      slot.sleepStart = start;
      slot.sleepEnd = end;
    } catch (_) {}
  }

  Future<void> _loadWorkouts(DateTime from, DateTime to) async {
    try {
      final points = await _health.getHealthDataFromTypes(
          types: const [HealthDataType.WORKOUT], startTime: from, endTime: to);
      // Bu aralıktaki günlerin eski listesini temizle.
      for (var d = dateOnly(from); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
        days[dayKey(d)]?.workouts.clear();
      }
      final seen = <String>{};
      for (final p in points) {
        if (!seen.add('${p.dateFrom.millisecondsSinceEpoch}')) continue;
        final v = p.value;
        final name = v is WorkoutHealthValue ? workoutName(v.workoutActivityType.name) : 'Egzersiz';
        _slot(p.dateFrom).workouts.add(Workout(name, p.dateFrom, p.dateTo.difference(p.dateFrom)));
      }
    } catch (_) {}
  }

  // ---------- Özetler ----------

  /// Son [n] günün (bugün hariç) adım ortalaması; veri yoksa null.
  int? averageSteps(DateTime before, [int n = 7]) {
    final list = [
      for (var i = 1; i <= n; i++)
        if (day(DateTime(before.year, before.month, before.day - i))?.steps case final s?)
          if (s > 0) s,
    ];
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) ~/ list.length;
  }

  /// Son 7 gecenin ortalama yatış saati (dakika; gece yarısından sonrası 24*60 üstü).
  int? averageBedtime() {
    final today = dateOnly(DateTime.now());
    final list = <int>[];
    for (var i = 0; i < 7; i++) {
      final s = day(DateTime(today.year, today.month, today.day - i))?.sleepStart;
      if (s == null) continue;
      var m = s.hour * 60 + s.minute;
      if (m < 12 * 60) m += 24 * 60; // 00:40 -> 24:40
      list.add(m);
    }
    if (list.length < 2) return null;
    return list.reduce((a, b) => a + b) ~/ list.length;
  }

  /// Son 7 gecenin ortalama uykusu.
  Duration? averageSleep() {
    final today = dateOnly(DateTime.now());
    final list = [
      for (var i = 0; i < 7; i++)
        if (day(DateTime(today.year, today.month, today.day - i))?.sleep case final s?) s,
    ];
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) ~/ list.length;
  }
}

/// Health Connect egzersiz türünün Türkçesi.
String workoutName(String type) => switch (type) {
      'RUNNING' || 'RUNNING_TREADMILL' => 'Koşu',
      'WALKING' => 'Yürüyüş',
      'HIKING' => 'Doğa yürüyüşü',
      'BIKING' || 'BIKING_STATIONARY' => 'Bisiklet',
      'SWIMMING_POOL' || 'SWIMMING_OPEN_WATER' || 'SWIMMING' => 'Yüzme',
      'YOGA' => 'Yoga',
      'PILATES' => 'Pilates',
      'STRENGTH_TRAINING' || 'WEIGHTLIFTING' => 'Ağırlık',
      'HIGH_INTENSITY_INTERVAL_TRAINING' => 'HIIT',
      'SOCCER' => 'Futbol',
      'BASKETBALL' => 'Basketbol',
      'TENNIS' => 'Tenis',
      'DANCING' => 'Dans',
      'ELLIPTICAL' => 'Eliptik',
      'ROWING' || 'ROWING_MACHINE' => 'Kürek',
      'STAIR_CLIMBING' || 'STAIR_CLIMBING_MACHINE' => 'Merdiven',
      _ => 'Egzersiz',
    };

/// 8450 -> "8.450"
String fmtSteps(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}
