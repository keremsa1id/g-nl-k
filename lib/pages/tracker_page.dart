import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../trackers.dart';
import '../widgets.dart';
import 'tracker_setup.dart';
import 'tracker_stats_page.dart';

/// Bir alışkanlık takibinin ana sayfası (sigara, alkol, gazlı içecek…).
class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key, required this.trackerId});

  final String trackerId;

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  final s = Store.instance;
  Timer? _ticker;

  Tracker get t => s.trackerById(widget.trackerId)!;
  String get _pack => t.packName.toLowerCase();

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
    setState(() => this.t.events
      ..add(t)
      ..sort());
    await s.saveTrackers();
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
      helpText: 'Ne zaman?',
    );
    if (t == null) return;
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (at.isAfter(now)) at = at.subtract(const Duration(days: 1));
    await _logSmoke(at);
  }

  Future<void> _removeSmoke(DateTime t) async {
    setState(() => this.t.events.remove(t));
    await s.saveTrackers();
  }

  Future<void> _startCounter() async {
    setState(() => t.quitStart = DateTime.now());
    await s.saveTrackers();
  }

  Future<void> _addPack() async {
    final priceCtrl = TextEditingController(text: _num(t.packPrice));
    final countCtrl = TextEditingController(
        text: (t.packs.isEmpty ? t.packSize : t.packs.last.count).toString());
    var qty = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final price = double.tryParse(priceCtrl.text.replaceAll(',', '.').trim()) ?? 0;
          return AlertDialog(
            title: Text('${t.packName} aldım'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Kaç paket
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surface1,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      _stepButton(Icons.remove_rounded,
                          qty > 1 ? () => setLocal(() => qty--) : null),
                      Expanded(
                        child: Column(
                          children: [
                            Text('$qty',
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                            Text(_pack,
                                style: const TextStyle(fontSize: 12, color: Colors.white60)),
                          ],
                        ),
                      ),
                      _stepButton(Icons.add_rounded, () => setLocal(() => qty++)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: priceCtrl,
                  onChanged: (_) => setLocal(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '${t.packName} fiyatı (₺)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: countCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Bir ${_pack} kaç ${t.unit}'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Toplam', style: TextStyle(color: Colors.white60)),
                    const Spacer(),
                    Text('${_num(price * qty)} ₺',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.redBright)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(qty > 1 ? '$qty $_pack ekle' : 'Ekle')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final count = int.tryParse(countCtrl.text.trim()) ?? t.packSize;
    final now = DateTime.now();
    setState(() {
      for (var i = 0; i < qty; i++) {
        t.packs.add(PackPurchase(time: now, price: price, count: count <= 0 ? t.packSize : count));
      }
      t.packPrice = price; // sonraki alımda bu fiyat gelsin
    });
    await s.saveTrackers();
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) => IconButton.filled(
        onPressed: onTap,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.surface3,
          fixedSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  Future<void> _removePack(PackPurchase p) async {
    setState(() => t.packs.remove(p));
    await s.saveTrackers();
  }

  Future<void> _edit() async {
    final edited = await showTrackerSetup(context, existing: t);
    if (edited != null && mounted) setState(() {});
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.name} takibi kaldırılsın mı?'),
        content: const Text('Bu takibe ait bütün kayıtlar silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaldır')),
        ],
      ),
    );
    if (ok == true) await s.removeTracker(t);
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
    // Takip az önce kaldırıldıysa alt menü yenilenene kadar boş çiz.
    if (s.trackerById(widget.trackerId) == null) return const SizedBox.shrink();
    final t = this.t;
    final start = t.counterStart;
    final elapsed = start == null ? null : now.difference(start);

    final today = t.countOn(now);
    final weekAgo = now.subtract(const Duration(days: 7));
    final week = t.events.where((e) => e.isAfter(weekAgo)).length;

    var longest = elapsed ?? Duration.zero;
    for (var i = 1; i < t.events.length; i++) {
      final g = t.events[i].difference(t.events[i - 1]);
      if (g > longest) longest = g;
    }

    final totalBought = t.packs.fold<int>(0, (a, p) => a + p.count);
    final totalSpent = t.packs.fold<double>(0, (a, p) => a + p.price);
    int? remaining;
    if (t.packs.isNotEmpty) {
      final first = t.packs.first.time;
      final used = t.events.where((e) => !e.isBefore(first)).length;
      final r = totalBought - used;
      remaining = r < 0 ? 0 : r;
    }

    // Geçmiş: her gün için kayıtlar ve alımlar (son 30 gün).
    final days = <DateTime>{
      dateOnly(now), // bugün her zaman görünsün
      for (final e in t.events) dateOnly(e),
      for (final p in t.packs) dateOnly(p.time),
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              eyebrow: '${t.emoji}  ${t.name} takibi',
              title: elapsed == null ? 'Hazır mısın?' : 'Temiz kalıyorsun',
              actions: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (v) => switch (v) {
                      'stats' => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => TrackerStatsPage(trackerId: t.id))),
                      'edit' => _edit(),
                      _ => _remove(),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'stats',
                          child: ListTile(
                              leading: Icon(Icons.insights_rounded),
                              title: Text('Detaylı istatistik'))),
                      PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                              leading: Icon(Icons.tune_rounded), title: Text('Takibi düzenle'))),
                      PopupMenuItem(
                          value: 'remove',
                          child: ListTile(
                              leading: Icon(Icons.delete_outline_rounded),
                              title: Text('Takibi kaldır'))),
                    ],
                  ),
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
                          icon: Text(t.emoji, style: const TextStyle(fontSize: 20)),
                          label: Text(t.logLabel),
                        ),
                      ),
                      if (t.tracksPurchases) ...[
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
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Geçmiş bir saati girmek için "${t.logLabel}" butonuna basılı tut.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  // İstatistikler (bento)
                  SectionLabel(
                    'İstatistikler',
                    trailing: TextButton.icon(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute<void>(
                              builder: (_) => TrackerStatsPage(trackerId: t.id))),
                      icon: const Icon(Icons.insights_rounded, size: 18),
                      label: const Text('Detaylı'),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(child: _stat(context, 'Bugün', '$today', t.unit)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _stat(context, '7 gün', '$week',
                              'ort. ${(week / 7).toStringAsFixed(1)}/gün')),
                      const SizedBox(width: 10),
                      Expanded(child: _stat(context, 'Toplam', '${t.events.length}', 'kayıt')),
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
                  if (t.tracksPurchases) ...[
                    const SizedBox(height: 10),
                    _wideStat(
                      context,
                      icon: Icons.account_balance_wallet_outlined,
                      label: '${t.packName} alımları',
                      value: '${_num(totalSpent)} ₺',
                      sub: '${t.packs.length} $_pack alındı · '
                          '${remaining == null ? 'kalan bilinmiyor' : 'tahmini $remaining ${t.unit} kaldı'}',
                      onTap: _addPack,
                    ),
                  ],
                  const SizedBox(height: 28),
                  const SectionLabel('Geçmiş'),
                  for (final day in days.take(30)) _dayCard(context, day, now),
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
          Text(t.emoji, style: const TextStyle(fontSize: 40)),
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
                painter: RingPainter(v),
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
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.all(16),
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
          if (onTap != null) ...[
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: AppTheme.red, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
            ),
          ],
        ],
      ),
    );
    return Container(
      decoration: _boxDecoration().copyWith(
        gradient: highlight
            ? LinearGradient(colors: [AppTheme.red.withValues(alpha: 0.22), AppTheme.surface1])
            : null,
        border: Border.all(
            color: highlight ? AppTheme.red.withValues(alpha: 0.45) : AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? row
          : Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, child: row),
            ),
    );
  }

  /// Bir günün özeti: tek kayıt satırı ve tek alım satırı, sayılarıyla.
  Widget _dayCard(BuildContext context, DateTime day, DateTime now) {
    final theme = Theme.of(context);
    final isToday = sameDay(day, now);
    final t = this.t;
    final smokes = t.events.where((e) => sameDay(e, day)).toList();
    final packs = t.packs.where((p) => sameDay(p.time, day)).toList();
    final spent = packs.fold<double>(0, (a, p) => a + p.price);
    final times = smokes.reversed.map((e) => '${two(e.hour)}:${two(e.minute)}').toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(_dayLabel(day, now),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Container(
            decoration: _boxDecoration(),
            child: Column(
              children: [
                if (smokes.isNotEmpty || isToday)
                  _summaryRow(
                    context,
                    icon: Text(t.emoji, style: const TextStyle(fontSize: 20)),
                    accent: true,
                    title: t.name,
                    subtitle: times.isEmpty
                        ? 'Bugün hiç yok 👏'
                        : times.length > 6
                            ? '${times.take(6).join(', ')} …'
                            : times.join(', '),
                    count: smokes.length,
                    unit: t.unit,
                    onMinus: smokes.isEmpty ? null : () => _removeSmoke(smokes.last),
                    onPlus: isToday ? _logSmoke : null,
                  ),
                if (t.tracksPurchases &&
                    (smokes.isNotEmpty || isToday) &&
                    (packs.isNotEmpty || isToday))
                  const Divider(indent: 64),
                if (t.tracksPurchases && (packs.isNotEmpty || isToday))
                  _summaryRow(
                    context,
                    icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                    accent: false,
                    title: t.packName,
                    subtitle: packs.isEmpty
                        ? '${t.packName} alınmadı'
                        : '${packs.first.count} ${t.unit} · ${_num(spent)} ₺',
                    count: packs.length,
                    unit: _pack,
                    onMinus: packs.isEmpty ? null : () => _removePack(packs.last),
                    onPlus: isToday ? _addPack : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required Widget icon,
    required bool accent,
    required String title,
    required String subtitle,
    required int count,
    required String unit,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent ? AppTheme.red.withValues(alpha: 0.15) : AppTheme.surface3,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(color: accent ? AppTheme.redBright : scheme.onSurfaceVariant),
              child: icon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          _miniStep(Icons.remove_rounded, onMinus),
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text('$count',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: accent && count > 0 ? AppTheme.redBright : scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
                Text(unit, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (onPlus != null) _miniStep(Icons.add_rounded, onPlus, filled: true),
        ],
      ),
    );
  }

  Widget _miniStep(IconData icon, VoidCallback? onTap, {bool filled = false}) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: filled ? AppTheme.red : AppTheme.surface2,
          foregroundColor: filled ? Colors.white : null,
          disabledBackgroundColor: Colors.transparent,
          fixedSize: const Size(36, 36),
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(color: filled || onTap == null ? Colors.transparent : AppTheme.border),
          ),
        ),
      );
}
