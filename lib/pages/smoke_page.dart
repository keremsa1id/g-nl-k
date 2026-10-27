import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets.dart';

class SmokePage extends StatefulWidget {
  const SmokePage({super.key});

  @override
  State<SmokePage> createState() => _SmokePageState();
}

class _SmokePageState extends State<SmokePage> {
  final s = Store.instance;
  Timer? _ticker;

  static const _milestones = <(Duration, String)>[
    (Duration(hours: 1), '1 saat'),
    (Duration(hours: 6), '6 saat'),
    (Duration(hours: 12), '12 saat'),
    (Duration(days: 1), '1 gün'),
    (Duration(days: 2), '2 gün'),
    (Duration(days: 3), '3 gün'),
    (Duration(days: 7), '1 hafta'),
    (Duration(days: 14), '2 hafta'),
    (Duration(days: 30), '1 ay'),
    (Duration(days: 90), '3 ay'),
    (Duration(days: 180), '6 ay'),
    (Duration(days: 365), '1 yıl'),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------- Aksiyonlar ----------

  Future<void> _logSmoke([DateTime? at]) async {
    final t = at ?? DateTime.now();
    setState(() => s.smokes
      ..add(t)
      ..sort());
    await s.saveSmoking();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Kaydedildi, sayaç sıfırlandı'),
        action: SnackBarAction(label: 'Geri al', onPressed: () => _removeSmoke(t)),
      ));
  }

  Future<void> _logPastSmoke() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Ne zaman içtin?',
    );
    if (t == null) return;
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (at.isAfter(now)) at = at.subtract(const Duration(days: 1));
    await _logSmoke(at);
  }

  Future<void> _removeSmoke(DateTime t) async {
    setState(() => s.smokes.remove(t));
    await s.saveSmoking();
  }

  Future<void> _startCounter() async {
    setState(() => s.quitStart = DateTime.now());
    await s.saveSmoking();
  }

  Future<void> _addPack() async {
    final priceCtrl = TextEditingController(
        text: s.packs.isEmpty ? '' : _num(s.packs.last.price));
    final countCtrl = TextEditingController(
        text: (s.packs.isEmpty ? 20 : s.packs.last.count).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paket aldım'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Fiyat (₺)', hintText: 'örn. 100'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Paketteki adet'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ekle')),
        ],
      ),
    );
    if (ok != true) return;
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final count = int.tryParse(countCtrl.text.trim()) ?? 20;
    setState(() => s.packs.add(PackPurchase(
          time: DateTime.now(),
          price: price,
          count: count <= 0 ? 20 : count,
        )));
    await s.saveSmoking();
  }

  Future<void> _removePack(PackPurchase p) async {
    setState(() => s.packs.remove(p));
    await s.saveSmoking();
  }

  // ---------- Biçimlendirme ----------

  static String _num(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _hms(Duration d) =>
      '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';

  static String _short(Duration d) {
    if (d.inDays > 0) return '${d.inDays} g ${d.inHours % 24} sa';
    if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    return '${d.inMinutes} dk';
  }

  static String _dayLabel(DateTime d, DateTime now) {
    if (sameDay(d, now)) return 'Bugün';
    if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Dün';
    return '${d.day} ${trMonths[d.month - 1]}, ${trWeekdays[d.weekday - 1]}';
  }

  /// Sıradaki hedefe ilerleme (0..1) ve hedefin adı; hepsi tamamsa adı null.
  (double, String?) _progress(Duration elapsed) {
    var prev = Duration.zero;
    for (final (target, label) in _milestones) {
      if (elapsed < target) {
        final p = (elapsed - prev).inSeconds / (target - prev).inSeconds;
        return (p.clamp(0.0, 1.0), label);
      }
      prev = target;
    }
    return (1.0, null);
  }

  // ---------- Arayüz ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final start = s.counterStart;
    final elapsed = start == null ? null : now.difference(start);

    final today = s.smokes.where((t) => sameDay(t, now)).length;
    final weekAgo = now.subtract(const Duration(days: 7));
    final week = s.smokes.where((t) => t.isAfter(weekAgo)).length;

    var longest = elapsed ?? Duration.zero;
    for (var i = 1; i < s.smokes.length; i++) {
      final g = s.smokes[i].difference(s.smokes[i - 1]);
      if (g > longest) longest = g;
    }

    final totalBought = s.packs.fold<int>(0, (a, p) => a + p.count);
    final totalSpent = s.packs.fold<double>(0, (a, p) => a + p.price);
    int? remaining;
    if (s.packs.isNotEmpty) {
      final first = s.packs.first.time;
      final used = s.smokes.where((t) => !t.isBefore(first)).length;
      final r = totalBought - used;
      remaining = r < 0 ? 0 : r;
    }

    final entries = <(DateTime, PackPurchase?)>[
      for (final t in s.smokes) (t, null),
      for (final p in s.packs) (p.time, p),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    // Geçmişi günlere böl.
    final byDay = <DateTime, List<(DateTime, PackPurchase?)>>{};
    for (final e in entries.take(50)) {
      byDay.putIfAbsent(dateOnly(e.$1), () => []).add(e);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              eyebrow: 'Sigarayı bırak',
              title: elapsed == null ? 'Hazır mısın?' : 'Temiz kalıyorsun',
              actions: [
                SquareIconButton(
                  tooltip: 'Paket aldım',
                  icon: Icons.shopping_bag_outlined,
                  onPressed: _addPack,
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _hero(context, elapsed),
                  if (start != null) ...[
                    const SizedBox(height: 4),
                    Text('Başlangıç: ${fmtDateTime(start)}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 16),
                  _milestoneStrip(context, elapsed ?? Duration.zero),
                  const SizedBox(height: 20),
                  // Butonlar
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(60),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          onPressed: _logSmoke,
                          onLongPress: _logPastSmoke,
                          icon: const Icon(Icons.smoking_rooms_rounded),
                          label: const Text('Sigara içtim'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: _addPack,
                          child: const Icon(Icons.add_shopping_cart_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Geçmiş bir saati girmek için "Sigara içtim"e basılı tut.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  // İstatistikler (bento)
                  const SectionLabel('İstatistikler'),
                  Row(
                    children: [
                      Expanded(child: _stat(context, 'Bugün', '$today', 'sigara')),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _stat(context, '7 gün', '$week',
                              'ort. ${(week / 7).toStringAsFixed(1)}/gün')),
                      const SizedBox(width: 10),
                      Expanded(child: _stat(context, 'Toplam', '${s.smokes.length}', 'kayıt')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _wideStat(
                    context,
                    icon: Icons.emoji_events_rounded,
                    label: 'En uzun ara',
                    value: _short(longest),
                    sub: 'kişisel rekorun',
                    highlight: true,
                  ),
                  const SizedBox(height: 10),
                  _wideStat(
                    context,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Paketler',
                    value: '${_num(totalSpent)} ₺',
                    sub: '${s.packs.length} paket alındı · '
                        '${remaining == null ? 'kalan bilinmiyor' : 'tahmini $remaining adet kaldı'}',
                  ),
                  const SizedBox(height: 28),
                  const SectionLabel('Geçmiş'),
                  if (entries.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      decoration: _boxDecoration(),
                      child: Column(
                        children: [
                          Icon(Icons.history_rounded,
                              size: 40, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 8),
                          const Text('Henüz kayıt yok'),
                        ],
                      ),
                    ),
                  for (final MapEntry(key: day, value: list) in byDay.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text(_dayLabel(day, now),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Container(
                      decoration: _boxDecoration(),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (idx, (t, p)) in list.indexed) ...[
                            if (idx > 0) const Divider(indent: 64),
                            _historyTile(context, t, p),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (entries.isNotEmpty)
                    Text('Silmek için kaydı sola kaydır.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _boxDecoration() => BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      );

  /// Ortadaki halka sayaç.
  Widget _hero(BuildContext context, Duration? elapsed) {
    final theme = Theme.of(context);
    final (progress, next) = elapsed == null ? (0.0, null) : _progress(elapsed);

    Widget center;
    if (elapsed == null) {
      center = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smoke_free_rounded, size: 40, color: AppTheme.redBright),
          const SizedBox(height: 8),
          Text('Henüz kayıt yok', style: theme.textTheme.titleMedium),
          const SizedBox(height: 14),
          FilledButton(onPressed: _startCounter, child: const Text('Sayacı başlat')),
        ],
      );
    } else {
      final days = elapsed.inDays;
      final digits = theme.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: Colors.white,
        letterSpacing: -1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      center = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (days > 0) ...[
            Text('$days',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                )),
            const Text('GÜN',
                style: TextStyle(
                  color: AppTheme.redBright,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                )),
            const SizedBox(height: 6),
            Text(_hms(elapsed),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white70,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ] else ...[
            FittedBox(child: Text(_hms(elapsed), style: digits)),
            const SizedBox(height: 2),
            const Text('SA : DK : SN',
                style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              next == null ? 'Tüm hedefler tamam 🎉' : 'Hedef: $next · %${(progress * 100).floor()}',
              style: const TextStyle(
                  color: AppTheme.redBright, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
    }

    return Center(
      child: SizedBox(
        width: 270,
        height: 270,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Arka parıltı
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.red.withValues(alpha: 0.22),
                  Colors.transparent,
                ]),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CustomPaint(
                size: const Size.square(250),
                painter: _RingPainter(v),
              ),
            ),
            Padding(padding: const EdgeInsets.all(36), child: center),
          ],
        ),
      ),
    );
  }

  /// Yatay kayan hedef rozetleri.
  Widget _milestoneStrip(BuildContext context, Duration elapsed) {
    final scheme = Theme.of(context).colorScheme;
    final firstOpen = _milestones.indexWhere((m) => elapsed < m.$1);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _milestones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (target, label) = _milestones[i];
          final done = elapsed >= target;
          final current = i == firstOpen;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: done ? AppTheme.red : AppTheme.surface1,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: done || current ? AppTheme.red : AppTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.check_rounded : Icons.flag_outlined,
                  size: 16,
                  color: done
                      ? Colors.white
                      : current
                          ? AppTheme.redBright
                          : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: done
                          ? Colors.white
                          : current
                              ? AppTheme.redBright
                              : scheme.onSurfaceVariant,
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, String sub) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTheme.redBright,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _wideStat(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration().copyWith(
        gradient: highlight
            ? LinearGradient(colors: [AppTheme.red.withValues(alpha: 0.22), AppTheme.surface1])
            : null,
        border: Border.all(
            color: highlight ? AppTheme.red.withValues(alpha: 0.45) : AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppTheme.redBright),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _historyTile(BuildContext context, DateTime t, PackPurchase? p) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('${p == null ? 's' : 'p'}${t.microsecondsSinceEpoch}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppTheme.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => p == null ? _removeSmoke(t) : _removePack(p),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: p == null ? AppTheme.red.withValues(alpha: 0.15) : AppTheme.surface3,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            p == null ? Icons.smoking_rooms_rounded : Icons.shopping_bag_outlined,
            size: 20,
            color: p == null ? AppTheme.redBright : scheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          p == null ? 'Sigara' : 'Paket · ${p.count} adet',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: p != null && p.price > 0 ? Text('${_num(p.price)} ₺') : null,
        trailing: Text('${two(t.hour)}:${two(t.minute)}',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ),
    );
  }
}

/// Kırmızı gradyanlı ilerleme halkası.
class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);

    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.07),
    );

    if (progress <= 0) return;
    final sweep = math.pi * 2 * progress;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: const [AppTheme.redDeep, AppTheme.red, AppTheme.redBright],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(arcRect, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
