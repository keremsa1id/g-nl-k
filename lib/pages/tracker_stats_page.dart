import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../trackers.dart';
import '../widgets.dart';

/// Bir takibin kayıt saatlerini ve günlerini inceleyen detaylı istatistik sayfası.
class TrackerStatsPage extends StatefulWidget {
  const TrackerStatsPage({super.key, required this.trackerId});

  final String trackerId;

  @override
  State<TrackerStatsPage> createState() => _TrackerStatsPageState();
}

class _TrackerStatsPageState extends State<TrackerStatsPage> {
  Tracker get _t => Store.instance.trackerById(widget.trackerId)!;

  static const _tabular = [FontFeature.tabularFigures()];

  /// Dönem (gün); 0 = tüm kayıtlar.
  int _period = 30;
  final _expanded = <DateTime>{};

  static DateTime _add(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  static String _hm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

  static String _gap(Duration d) {
    if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    return '${d.inMinutes} dk';
  }

  @override
  Widget build(BuildContext context) {
    final s = _t;
    final unit = s.unit;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final today = dateOnly(DateTime.now());

    final first = s.events.isEmpty ? today : dateOnly(s.events.first);
    final from = _period == 0 ? first : _add(today, -(_period - 1));
    final dayCount = today.difference(from).inDays + 1;
    final smokes = s.events.where((t) => !dateOnly(t).isBefore(from)).toList();

    // Güne göre grupla
    final byDay = <DateTime, List<DateTime>>{};
    for (final t in smokes) {
      byDay.putIfAbsent(dateOnly(t), () => []).add(t);
    }

    // Saat ve hafta günü dağılımı
    final hours = List<int>.filled(24, 0);
    final weekdays = List<int>.filled(7, 0);
    for (final t in smokes) {
      hours[t.hour]++;
      weekdays[t.weekday - 1]++;
    }
    final weekdayDays = List<int>.filled(7, 0); // dönemde her hafta gününden kaç tane var
    for (var k = 0; k < dayCount; k++) {
      weekdayDays[_add(from, k).weekday - 1]++;
    }
    var peakHour = 0;
    for (var h = 1; h < 24; h++) {
      if (hours[h] > hours[peakHour]) peakHour = h;
    }

    // Aynı gün içindeki aralar
    final gaps = <Duration>[];
    for (final list in byDay.values) {
      for (var i = 1; i < list.length; i++) {
        gaps.add(list[i].difference(list[i - 1]));
      }
    }
    final avgGap = gaps.isEmpty
        ? null
        : Duration(seconds: gaps.fold<int>(0, (a, g) => a + g.inSeconds) ~/ gaps.length);

    // İlk ve son kaydın saat ortalaması
    int? avgFirst, avgLast;
    if (byDay.isNotEmpty) {
      var f = 0, l = 0;
      for (final list in byDay.values) {
        f += list.first.hour * 60 + list.first.minute;
        l += list.last.hour * 60 + list.last.minute;
      }
      avgFirst = f ~/ byDay.length;
      avgLast = l ~/ byDay.length;
    }

    // Zaman dilimleri
    final slots = <(String, String, int)>[
      ('🌅', 'Sabah · 05–12', smokes.where((t) => t.hour >= 5 && t.hour < 12).length),
      ('☀️', 'Öğle · 12–17', smokes.where((t) => t.hour >= 12 && t.hour < 17).length),
      ('🌆', 'Akşam · 17–22', smokes.where((t) => t.hour >= 17 && t.hour < 22).length),
      ('🌙', 'Gece · 22–05', smokes.where((t) => t.hour >= 22 || t.hour < 5).length),
    ];

    // Kayıt başına tahmini maliyet (son paketin fiyatı / adedi)
    final unitCost =
        s.packs.isEmpty || s.packs.last.count == 0 ? null : s.packs.last.price / s.packs.last.count;

    // Günlük grafik (en fazla son 90 gün)
    final chartDays = dayCount > 90 ? 90 : dayCount;
    final chartFrom = _add(today, -(chartDays - 1));
    final daily = [
      for (var k = 0; k < chartDays; k++) byDay[_add(chartFrom, k)]?.length ?? 0,
    ];

    final tableDays = [for (var k = 0; k < dayCount; k++) _add(today, -k)];

    return Scaffold(
      appBar: AppBar(title: Text('${s.emoji} ${s.name} istatistikleri')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 7, label: Text('7 gün')),
              ButtonSegment(value: 30, label: Text('30 gün')),
              ButtonSegment(value: 90, label: Text('90 gün')),
              ButtonSegment(value: 0, label: Text('Tümü')),
            ],
            selected: {_period},
            onSelectionChanged: (v) => setState(() => _period = v.first),
          ),
          const SizedBox(height: 16),
          // Özet kutuları
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              _tile('Toplam', '${smokes.length}', '$unit · $dayCount gün'),
              _tile('Günlük ortalama', (smokes.length / dayCount).toStringAsFixed(1),
                  unitCost == null
                      ? '$unit / gün'
                      : '≈ ${(smokes.length / dayCount * unitCost).toStringAsFixed(0)} ₺ / gün'),
              _tile('Ortalama ara', avgGap == null ? '–' : _gap(avgGap), 'aynı gün içinde'),
              _tile('En yoğun saat', smokes.isEmpty ? '–' : '${two(peakHour)}:00',
                  smokes.isEmpty ? '' : '${hours[peakHour]} $unit'),
              _tile('Günün ilki', avgFirst == null ? '–' : fmtMinutes(avgFirst), 'ortalama saat'),
              _tile('Günün sonuncusu', avgLast == null ? '–' : fmtMinutes(avgLast), 'ortalama saat'),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('Saatlere göre'),
          _card(_hourChart(hours, peakHour, muted)),
          const SizedBox(height: 24),
          const SectionLabel('Zaman dilimleri'),
          _card(Column(
            children: [
              for (final (emoji, label, n) in slots)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      SizedBox(
                          width: 104,
                          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: smokes.isEmpty ? 0 : n / smokes.length,
                            minHeight: 10,
                            backgroundColor: AppTheme.surface3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 64,
                        child: Text(
                            smokes.isEmpty ? '0' : '$n · %${(n * 100 / smokes.length).round()}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, fontFeatures: _tabular)),
                      ),
                    ],
                  ),
                ),
            ],
          )),
          const SizedBox(height: 24),
          const SectionLabel('Haftanın günlerine göre · günlük ortalama'),
          _card(_weekdayChart(weekdays, weekdayDays, muted)),
          const SizedBox(height: 24),
          SectionLabel('Günlük sayı · son $chartDays gün'),
          _card(_dailyChart(daily, chartFrom, muted)),
          const SizedBox(height: 24),
          const SectionLabel('Gün gün tablo'),
          _table(tableDays, byDay, unitCost, muted),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );

  Widget _tile(String label, String value, String sub) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.redBright, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, fontFeatures: _tabular)),
            ),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
      );

  /// 24 sütunlu saat grafiği; en yoğun saat parlak kırmızı.
  Widget _hourChart(List<int> hours, int peak, Color muted) {
    final maxV = hours.reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var h = 0; h < 24; h++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Tooltip(
                      message: '${two(h)}:00 – ${hours[h]} ${_t.unit}',
                      child: FractionallySizedBox(
                        heightFactor: maxV == 0 ? 0.02 : (hours[h] / maxV).clamp(0.02, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: hours[h] == 0
                                ? AppTheme.surface3
                                : h == peak
                                    ? AppTheme.redBright
                                    : AppTheme.red.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var h = 0; h < 24; h++)
              Expanded(
                child: Text(h % 3 == 0 ? '$h' : '',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: muted)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _weekdayChart(List<int> counts, List<int> days, Color muted) {
    final avgs = [for (var i = 0; i < 7; i++) days[i] == 0 ? 0.0 : counts[i] / days[i]];
    final maxV = avgs.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(avgs[i] == 0 ? '' : avgs[i].toStringAsFixed(1),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Container(
                    width: 22,
                    height: maxV == 0 ? 4 : (avgs[i] / maxV * 80).clamp(4.0, 80.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: avgs[i] == maxV && maxV > 0
                            ? const [AppTheme.red, AppTheme.redBright]
                            : [AppTheme.redDeep, AppTheme.red.withValues(alpha: 0.7)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(trWeekdaysShort[i],
                      style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dailyChart(List<int> daily, DateTime from, Color muted) {
    final maxV = daily.isEmpty ? 0 : daily.reduce((a, b) => a > b ? a : b);
    final avg = daily.isEmpty ? 0.0 : daily.fold<int>(0, (a, b) => a + b) / daily.length;
    final last = _add(from, daily.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (k, v) in daily.indexed)
                    Expanded(
                      child: Tooltip(
                        message: '${fmtDate(_add(from, k))}: $v',
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: daily.length > 40 ? 0.5 : 1.5),
                          child: FractionallySizedBox(
                            heightFactor: maxV == 0 ? 0.02 : (v / maxV).clamp(0.02, 1.0),
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                color: v == 0
                                    ? AppTheme.surface3
                                    : v > avg
                                        ? AppTheme.redBright
                                        : AppTheme.red.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Ortalama çizgisi
              if (maxV > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 100 * avg / maxV,
                  child: Container(height: 1, color: Colors.white38),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('${from.day} ${trMonths[from.month - 1].substring(0, 3)}',
                style: TextStyle(fontSize: 10, color: muted)),
            const Spacer(),
            Text('— ortalama ${avg.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 10, color: Colors.white60)),
            const Spacer(),
            Text('${last.day} ${trMonths[last.month - 1].substring(0, 3)}',
                style: TextStyle(fontSize: 10, color: muted)),
          ],
        ),
      ],
    );
  }

  /// Her gün bir satır: tarih, adet, ilk, son, ortalama ara, maliyet. Dokununca saatler açılır.
  Widget _table(List<DateTime> days, Map<DateTime, List<DateTime>> byDay, double? unitCost,
      Color muted) {
    const head = TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.redBright);
    const cell = TextStyle(fontSize: 12, fontFeatures: _tabular);
    final rows = days.where((d) => byDay.containsKey(d) || days.length <= 31).toList();

    Widget row(List<Widget> cells) => Row(
          children: [
            Expanded(flex: 26, child: cells[0]),
            Expanded(flex: 12, child: Center(child: cells[1])),
            Expanded(flex: 14, child: Center(child: cells[2])),
            Expanded(flex: 14, child: Center(child: cells[3])),
            Expanded(flex: 18, child: Center(child: cells[4])),
            if (unitCost != null) Expanded(flex: 14, child: Align(alignment: Alignment.centerRight, child: cells[5])),
          ],
        );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppTheme.surface2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: row(const [
              Text('TARİH', style: head),
              Text('ADET', style: head),
              Text('İLK', style: head),
              Text('SON', style: head),
              Text('ORT. ARA', style: head),
              Text('₺', style: head),
            ]),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Bu dönemde kayıt yok'),
            ),
          for (final (idx, d) in rows.indexed) ...[
            if (idx > 0) const Divider(),
            Builder(builder: (_) {
              final list = byDay[d] ?? const <DateTime>[];
              final n = list.length;
              Duration? avg;
              if (n > 1) {
                avg = Duration(seconds: list.last.difference(list.first).inSeconds ~/ (n - 1));
              }
              final open = _expanded.contains(d);
              return InkWell(
                onTap: n == 0
                    ? null
                    : () => setState(() => open ? _expanded.remove(d) : _expanded.add(d)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    children: [
                      row([
                        Text(
                            '${d.day} ${trMonths[d.month - 1].substring(0, 3)} '
                            '${trWeekdaysShort[d.weekday - 1]}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: n == 0 ? muted : null)),
                        Text('$n',
                            style: cell.copyWith(
                                fontWeight: FontWeight.w800,
                                color: n == 0 ? const Color(0xFF2EC4B6) : AppTheme.redBright)),
                        Text(n == 0 ? '–' : _hm(list.first), style: cell),
                        Text(n == 0 ? '–' : _hm(list.last), style: cell),
                        Text(avg == null ? '–' : _gap(avg), style: cell),
                        Text(unitCost == null || n == 0 ? '–' : (n * unitCost).toStringAsFixed(0),
                            style: cell),
                      ]),
                      if (open) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in list)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.red.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(_hm(t),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.redBright,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: _tabular)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
