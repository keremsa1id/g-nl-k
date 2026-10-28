import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../categories.dart';
import '../models.dart';
import '../storage.dart';
import '../streaks.dart';
import '../theme.dart';
import '../trackers.dart';
import '../widgets.dart';

/// Haftalık rapor, kategori dağılımı ve spor ile takiplerin (sigara, alkol…) ilişkisi.
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  /// Grafik renkleri, kategori sırasına göre; sonuncusu "Diğer".
  static const _chartColors = <Color>[
    Color(0xFFE53935),
    Color(0xFF4DA3FF),
    Color(0xFFFFB020),
    Color(0xFF9B5DE5),
    Color(0xFFFF7A45),
    Color(0xFF5C6BC0),
    Color(0xFF2EC4B6),
    Color(0xFF66BB6A),
    Color(0xFF29B6F6),
    Color(0xFFF06292),
    Color(0xFF757575),
  ];

  static Color _catColor(int? cat) =>
      _chartColors[cat == null || cat < 0 || cat >= categories.length ? categories.length : cat];

  static String _catName(int? cat) => categoryOf(cat)?.name ?? 'Diğer';

  static DateTime _add(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  @override
  Widget build(BuildContext context) {
    final store = Store.instance;
    final today = dateOnly(DateTime.now());
    final monday = _add(today, -(today.weekday - 1));
    final lastMonday = _add(monday, -7);
    final lastSunday = _add(monday, -1);

    // Bu hafta / geçen hafta tamamlama oranı
    var done = 0, total = 0, lastDone = 0, lastTotal = 0;
    final catTally = <int, (int, int)>{};
    for (final i in store.items) {
      final (d, t) = store.tally(i, monday, today);
      done += d;
      total += t;
      final key = i.category ?? -1;
      final prev = catTally[key] ?? (0, 0);
      catTally[key] = (prev.$1 + d, prev.$2 + t);
      final (ld, lt) = store.tally(i, lastMonday, lastSunday);
      lastDone += ld;
      lastTotal += lt;
    }
    final rate = total == 0 ? null : done / total;
    final lastRate = lastTotal == 0 ? null : lastDone / lastTotal;

    // En iyi kategori
    int? bestCat;
    var bestCatRate = -1.0;
    catTally.forEach((k, v) {
      if (v.$2 == 0) return;
      final r = v.$1 / v.$2;
      if (r > bestCatRate || (r == bestCatRate && v.$1 > (catTally[bestCat]?.$1 ?? 0))) {
        bestCatRate = r;
        bestCat = k;
      }
    });

    // En uzun aktif seri
    ScheduleItem? streakItem;
    var streakN = 0;
    for (final i in store.items) {
      final n = store.streak(i, today);
      if (n > streakN) {
        streakN = n;
        streakItem = i;
      }
    }

    // Günlük çubuklar (bu hafta)
    final daily = <(int, int)>[];
    for (var k = 0; k < 7; k++) {
      final d = _add(monday, k);
      var dd = 0, tt = 0;
      if (!d.isAfter(today)) {
        for (final i in store.items) {
          if (!i.occursOn(d)) continue;
          tt++;
          if (store.isDone(i, d)) dd++;
        }
      }
      daily.add((dd, tt));
    }

    // Kategoriye göre planlanan süre (bu haftanın tamamı)
    final minutes = <int, int>{};
    for (var k = 0; k < 7; k++) {
      final d = _add(monday, k);
      for (final i in store.items) {
        if (!i.occursOn(d)) continue;
        final key = i.category ?? -1;
        minutes[key] = (minutes[key] ?? 0) + i.durationMinutes;
      }
    }
    final catList = minutes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalMin = catList.fold<int>(0, (a, e) => a + e.value);

    // Spor yapılan günler (son 30 gün) — her takiple karşılaştırmak için
    final last30 = [for (var k = 0; k < 30; k++) _add(today, -k)];
    final sportDaySet = {
      for (final d in last30)
        if (store.items.any((i) => i.category == 0 && store.isDone(i, d))) d,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('İstatistikler')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _reportCard(context, rate, lastRate, done, total, bestCat, bestCatRate, streakItem,
              streakN),
          const SizedBox(height: 12),
          _dailyBars(context, daily, today, monday),
          const SizedBox(height: 24),
          const SectionLabel('Bu hafta zaman dağılımı'),
          _categoryCard(context, catList, totalMin),
          for (final t in store.trackers) ...[
            const SizedBox(height: 24),
            SectionLabel('Spor ve ${t.name.toLowerCase()} · son 30 gün'),
            _sportTrackerCard(
              context,
              t,
              sportDaySet.length,
              sportDaySet.fold<int>(0, (a, d) => a + t.countOn(d)),
              last30.length - sportDaySet.length,
              last30.where((d) => !sportDaySet.contains(d)).fold<int>(0, (a, d) => a + t.countOn(d)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reportCard(BuildContext context, double? rate, double? lastRate, int done, int total,
      int? bestCat, double bestCatRate, ScheduleItem? streakItem, int streakN) {
    final diff = rate != null && lastRate != null ? ((rate - lastRate) * 100).round() : null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.redDeep, Color(0xFF2A0507), AppTheme.black],
        ),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BU HAFTA',
              style: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rate == null ? '–' : '%${(rate * 100).round()}',
                  style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, height: 1)),
              const SizedBox(width: 10),
              if (diff != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      '${diff >= 0 ? '▲' : '▼'} %${diff.abs()} geçen haftaya göre',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(total == 0 ? 'Bu hafta için planlanmış etkinlik yok' : '$done/$total etkinlik tamamlandı',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _fact(
                  categoryOf(bestCat)?.icon ?? Icons.star_rounded,
                  'En iyi kategori',
                  bestCat == null
                      ? '–'
                      : '${_catName(bestCat)} · %${(bestCatRate * 100).round()}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _fact(
                  Icons.local_fire_department_rounded,
                  'En uzun aktif seri',
                  streakItem == null ? '–' : '${streakItem.title} · $streakN',
                  color: flameColor(streakN),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String label, String value, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dailyBars(BuildContext context, List<(int, int)> daily, DateTime today, DateTime monday) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (k, (d, t)) in daily.indexed)
            Expanded(
              child: Column(
                children: [
                  Text(t == 0 ? '' : '$d/$t', style: TextStyle(fontSize: 10, color: muted)),
                  const SizedBox(height: 4),
                  Container(
                    height: 80,
                    width: 18,
                    alignment: Alignment.bottomCenter,
                    decoration: BoxDecoration(
                      color: AppTheme.surface3,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: FractionallySizedBox(
                      heightFactor: t == 0 ? 0 : d / t,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [AppTheme.redDeep, AppTheme.redBright],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(trWeekdaysShort[k],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sameDay(_add(monday, k), today) ? AppTheme.redBright : muted,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _categoryCard(BuildContext context, List<MapEntry<int, int>> list, int totalMin) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: totalMin == 0
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Bu hafta planlanmış etkinlik yok')),
            )
          : Row(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(130),
                        painter: _DonutPainter([
                          for (final e in list) (e.value.toDouble(), _catColor(e.key)),
                        ]),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(fmtDuration(totalMin),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text('toplam', style: TextStyle(fontSize: 10, color: muted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      for (final e in list.take(6))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(categoryOf(e.key)?.icon ?? Icons.circle,
                                  size: 16, color: _catColor(e.key)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(_catName(e.key),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Text('%${(e.value * 100 / totalMin).round()}',
                                  style: TextStyle(fontSize: 12, color: muted)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sportTrackerCard(BuildContext context, Tracker t, int sportDays, int sportSmokes,
      int otherDays, int otherSmokes) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final box = BoxDecoration(
      color: AppTheme.surface1,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.border),
    );
    if (sportDays == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: box,
        child: Row(
          children: [
            const Icon(Icons.fitness_center_rounded, color: AppTheme.redBright),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  'Spor kategorisinde bir etkinlik ekleyip tamamladıkça, spor yaptığın '
                  'günlerle yapmadığın günlerdeki ${t.name.toLowerCase()} sayısı burada karşılaştırılacak.',
                  style: TextStyle(color: muted)),
            ),
          ],
        ),
      );
    }
    final withAvg = sportSmokes / sportDays;
    final withoutAvg = otherDays == 0 ? 0.0 : otherSmokes / otherDays;
    final maxAvg = math.max(math.max(withAvg, withoutAvg), 0.1);
    final better = withAvg < withoutAvg;

    Widget bar(String label, double v, Color color, int days) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${v.toStringAsFixed(1)} / gün',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v / maxAvg,
                  minHeight: 12,
                  color: color,
                  backgroundColor: AppTheme.surface3,
                ),
              ),
              const SizedBox(height: 2),
              Text('$days gün', style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar('💪 Spor yaptığın günler', withAvg, const Color(0xFF2EC4B6), sportDays),
          bar('🛋️ Spor yapmadığın günler', withoutAvg, AppTheme.red, otherDays),
          const SizedBox(height: 8),
          Text(
            better
                ? 'Spor yaptığın günlerde ortalama ${(withoutAvg - withAvg).toStringAsFixed(1)} '
                    '${t.unit} daha az. Devam! 🔥'
                : 'Spor yaptığın günlerde ${t.name.toLowerCase()} sayın düşmemiş görünüyor.',
            style: TextStyle(color: better ? const Color(0xFF2EC4B6) : muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Halka (donut) grafik.
class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments);

  final List<(double, Color)> segments;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 20.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final total = segments.fold<double>(0, (a, s) => a + s.$1);
    if (total <= 0) return;
    const gap = 0.04;
    var start = -math.pi / 2;
    for (final (v, color) in segments) {
      final sweep = math.pi * 2 * v / total;
      canvas.drawArc(
        rect,
        start + (segments.length > 1 ? gap / 2 : 0),
        math.max(sweep - (segments.length > 1 ? gap : 0), 0.001),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}
