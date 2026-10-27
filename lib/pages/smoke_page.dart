import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';

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

  static String _clock(Duration d) {
    final days = d.inDays;
    final hms = '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return days > 0 ? '$days gün  $hms' : hms;
  }

  static String _short(Duration d) {
    if (d.inDays > 0) return '${d.inDays} g ${d.inHours % 24} sa';
    if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    return '${d.inMinutes} dk';
  }

  // ---------- Arayüz ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Sigarayı Bırak')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sayaç
          Card(
            color: scheme.primaryContainer,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.smoke_free, size: 36, color: scheme.onPrimaryContainer),
                  const SizedBox(height: 8),
                  Text('Son sigaradan beri',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onPrimaryContainer)),
                  const SizedBox(height: 4),
                  if (elapsed == null) ...[
                    Text('Henüz kayıt yok',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(color: scheme.onPrimaryContainer)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _startCounter,
                      child: const Text('Sayacı şimdi başlat'),
                    ),
                  ] else ...[
                    FittedBox(
                      child: Text(
                        _clock(elapsed),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text('Başlangıç: ${fmtDateTime(start!)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onPrimaryContainer)),
                    const SizedBox(height: 12),
                    _milestone(context, elapsed),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Butonlar
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _logSmoke,
                  onLongPress: _logPastSmoke,
                  icon: const Icon(Icons.smoking_rooms),
                  label: const Text('Sigara içtim'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _addPack,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Paket aldım'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Geçmiş bir saati girmek için "Sigara içtim"e basılı tut.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          // İstatistikler
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              _stat(context, 'Bugün', '$today', 'sigara'),
              _stat(context, 'Son 7 gün', '$week', 'ort. ${(week / 7).toStringAsFixed(1)} / gün'),
              _stat(context, 'En uzun ara', _short(longest), 'rekorun'),
              _stat(context, 'Toplam içilen', '${s.smokes.length}', 'kayıtlı sigara'),
              _stat(context, 'Alınan paket', '${s.packs.length}', '${_num(totalSpent)} ₺ harcandı'),
              _stat(context, 'Paketten kalan', remaining == null ? '-' : '$remaining',
                  'tahmini adet'),
            ],
          ),
          const SizedBox(height: 20),
          Text('Geçmiş', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Henüz kayıt yok'),
            ),
          for (final (t, p) in entries.take(50))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(p == null ? Icons.smoking_rooms : Icons.shopping_bag_outlined),
              title: Text(p == null
                  ? 'Sigara'
                  : 'Paket (${p.count} adet${p.price > 0 ? ', ${_num(p.price)} ₺' : ''})'),
              subtitle: Text(fmtDateTime(t)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => p == null ? _removeSmoke(t) : _removePack(p),
              ),
            ),
        ],
      ),
    );
  }

  Widget _milestone(BuildContext context, Duration elapsed) {
    final scheme = Theme.of(context).colorScheme;
    Duration prev = Duration.zero;
    for (final (target, label) in _milestones) {
      if (elapsed < target) {
        final progress = (elapsed - prev).inSeconds / (target - prev).inSeconds;
        return Column(
          children: [
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Text('Sıradaki hedef: $label',
                style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12)),
          ],
        );
      }
      prev = target;
    }
    return Text('Tüm hedefler tamam! 🎉', style: TextStyle(color: scheme.onPrimaryContainer));
  }

  Widget _stat(BuildContext context, String label, String value, String sub) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(sub, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
