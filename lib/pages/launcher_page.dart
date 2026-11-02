import 'dart:async';

import 'package:flutter/material.dart';

import '../game.dart';
import '../health_data.dart';
import '../models.dart';
import '../notifications.dart';
import '../screen_time.dart';
import '../storage.dart';
import '../trackers.dart';
import '../widgets.dart';
import 'lungs.dart';
import 'profile_page.dart';
import 'tracker_setup.dart';

/// Uygulama açılınca gelen giriş ekranı: büyük kutucuklardan biri seçilince o bölüm açılır.
/// [onOpen]: alt menüdeki sekme (0 = Program, 1 = Sağlık, 2+ = takipler) ve Sağlık
/// sekmesindeyse alt sekme (0 = Sağlık, 1 = Ekran süresi).
class LauncherPage extends StatefulWidget {
  const LauncherPage({super.key, required this.onOpen});

  final void Function(int index, int? tab) onOpen;

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  final store = Store.instance;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _greeting(int hour) => switch (hour) {
        < 6 => 'İyi geceler',
        < 12 => 'Günaydın',
        < 18 => 'İyi günler',
        < 22 => 'İyi akşamlar',
        _ => 'İyi geceler',
      };

  static String _ago(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} gün ${d.inHours % 24} sa';
    if (d.inHours >= 1) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    return '${d.inMinutes} dk';
  }

  String _programText(DateTime now) {
    final today = dateOnly(now);
    final items = store.items.where((i) => i.occursOn(today)).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    if (items.isEmpty) return 'Bugün program boş · eklemek için dokun';
    final done = items.where((i) => store.isDone(i, today)).length;
    final nowMin = now.hour * 60 + now.minute;
    final next = items
        .where((i) => !store.isDone(i, today) && i.endMinutes > nowMin)
        .firstOrNull;
    final head = next == null
        ? (done == items.length ? '🎉 Hepsi tamam' : 'Kalanları işaretle')
        : next.startMinutes <= nowMin
            ? 'Şimdi: ${next.title}'
            : 'Sıradaki: ${next.title} · ${fmtMinutes(next.startMinutes)}';
    return '$head\n$done/${items.length} tamamlandı';
  }

  String _healthText() {
    final h = HealthData.instance;
    if (!h.connected) return 'Adım, uyku ve egzersiz';
    final d = h.day(DateTime.now());
    final parts = [
      if (d?.steps case final s?) '🚶 ${fmtSteps(s)} adım',
      if (d?.sleep case final s?) '😴 ${fmtDuration(s.inMinutes)} uyku',
    ];
    return parts.isEmpty ? 'Bugün henüz veri yok' : parts.join('\n');
  }

  String _screenText() {
    final m = Game.instance.screen[dayKey(DateTime.now())];
    if (m == null || m.isEmpty) return 'Sosyal medya, oyun, video…';
    final total = m.values.fold(Duration.zero, (a, b) => a + b);
    final social = m[AppGroup.social];
    return 'Bugün ${fmtUsage(total)}'
        '${social == null || social == Duration.zero ? '' : '\n📱 Sosyal ${fmtUsage(social)}'}';
  }

  String _trackerText(Tracker t, DateTime now) {
    final start = t.counterStart;
    final today = t.countOn(now);
    final lines = [
      start == null ? 'Sayacı başlat' : '⏱ Temiz: ${_ago(now.difference(start))}',
      if (isSmokingTracker(t))
        '🫁 Ciğer %${(lungDirt(t.events, now) * 100).round()} kirli'
      else
        'Bugün $today ${t.unit}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [Game.instance.changes, Notifier.changes, store.trackersChanged]),
      builder: (context, _) {
        final now = DateTime.now();
        final name = Game.instance.profile.name.trim();
        final trackers = store.trackers;
        final tiles = <Widget>[
          _Tile(
            emoji: '❤️',
            title: 'Sağlık',
            subtitle: _healthText(),
            colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
            onTap: () => widget.onOpen(1, 0),
          ),
          _Tile(
            emoji: '📱',
            title: 'Telefon kullanımı',
            subtitle: _screenText(),
            colors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
            onTap: () => widget.onOpen(1, 1),
          ),
          for (final (i, t) in trackers.indexed)
            _Tile(
              emoji: t.emoji,
              title: t.name,
              subtitle: _trackerText(t, now),
              colors: const [Color(0xFF6D4C41), Color(0xFF3E2723)],
              onTap: () => widget.onOpen(i + 2, null),
            ),
          if (trackers.isEmpty)
            _Tile(
              emoji: '🚭',
              title: 'Sigara / alışkanlık',
              subtitle: 'Takip eklemek için dokun',
              colors: const [Color(0xFF6D4C41), Color(0xFF3E2723)],
              onTap: () => showTrackerSetup(context),
            ),
        ];

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                PageHeader(
                  eyebrow: '${now.day} ${trMonths[now.month - 1]} ${trWeekdays[now.weekday - 1]}',
                  title: '${_greeting(now.hour)}${name.isEmpty ? '' : ', $name'}',
                  actions: const [ProfileButton()],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      SizedBox(
                        height: 160,
                        child: _Tile(
                          emoji: '📅',
                          title: 'Takvim',
                          subtitle: _programText(now),
                          colors: const [Color(0xFFE53935), Color(0xFF8E1B1B)],
                          onTap: () => widget.onOpen(0, null),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.92,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: tiles,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Bir bölüm açtıktan sonra alt menüden diğerlerine geçebilirsin; '
                        'geri tuşu bu ekrana döner.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 38)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
