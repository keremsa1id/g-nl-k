import 'package:flutter/material.dart';

import '../models.dart';
import '../screen_time.dart';
import '../theme.dart';
import '../widgets.dart';

/// Profildeki özet kart: bugünkü toplam, sosyal medya ve oyun süresi.
class ScreenTimeCard extends StatelessWidget {
  const ScreenTimeCard({super.key});

  Future<List<AppUsage>?> _today() async {
    if (!await ScreenTime.hasPermission()) return null;
    final now = DateTime.now();
    return ScreenTime.query(dateOnly(now), now);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Material(
      color: AppTheme.surface1,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => const ScreenTimePage())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: FutureBuilder<List<AppUsage>?>(
            future: ScreenTime.supported ? _today() : Future.value(null),
            builder: (context, snap) {
              final apps = snap.data;
              String sum(AppGroup g) => fmtUsage(apps!
                  .where((a) => a.group == g)
                  .fold(Duration.zero, (a, e) => a + e.duration));
              return Row(
                children: [
                  const Text('📱', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          apps == null
                              ? 'Telefon kullanımın'
                              : 'Bugün ${fmtUsage(apps.fold(Duration.zero, (a, e) => a + e.duration))} ekran süresi',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          apps == null
                              ? 'Sosyal medya, oyun ve video sürelerini gör'
                              : '💬 ${sum(AppGroup.social)} · 🎮 ${sum(AppGroup.game)} · 🎬 ${sum(AppGroup.video)}',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: muted),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Telefondaki uygulama kullanımı: sosyal medya, oyun, video… (Ayarlar > Dijital Denge verisi).
class ScreenTimePage extends StatefulWidget {
  const ScreenTimePage({super.key});

  @override
  State<ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<ScreenTimePage> with WidgetsBindingObserver {
  bool? _permission;
  int _range = 0; // 0 = bugün, 1 = dün, 2 = son 7 gün
  List<AppUsage>? _apps;
  List<Duration> _daily = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Ayarlardan izin verip geri dönünce yeniden dene.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  (DateTime, DateTime) _bounds() {
    final now = DateTime.now();
    final today = dateOnly(now);
    return switch (_range) {
      1 => (DateTime(today.year, today.month, today.day - 1), today),
      2 => (DateTime(today.year, today.month, today.day - 6), now),
      _ => (today, now),
    };
  }

  Future<void> _load() async {
    if (!ScreenTime.supported) {
      setState(() => _permission = false);
      return;
    }
    final ok = await ScreenTime.hasPermission();
    if (!mounted) return;
    if (!ok) {
      setState(() => _permission = false);
      return;
    }
    setState(() {
      _permission = true;
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _bounds();
      final apps = await ScreenTime.query(from, to);
      final today = dateOnly(DateTime.now());
      final daily = <Duration>[];
      for (var i = 6; i >= 0; i--) {
        final d = DateTime(today.year, today.month, today.day - i);
        final list = await ScreenTime.query(d, DateTime(d.year, d.month, d.day + 1));
        daily.add(list.fold(Duration.zero, (a, e) => a + e.duration));
      }
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _daily = daily;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kullanım verisi okunamadı';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📱 Ekran süresi')),
      body: switch (_permission) {
        null => const Center(child: CircularProgressIndicator()),
        false => _permissionView(context),
        true => _content(context),
      },
    );
  }

  Widget _permissionView(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (!ScreenTime.supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Ekran süresi sadece Android telefonda çalışır.',
              textAlign: TextAlign.center, style: TextStyle(color: muted)),
        ),
      );
    }
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.red,
                child: Text(n,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('📊', style: TextStyle(fontSize: 56), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('Telefonunu ne kadar kullanıyorsun?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Sosyal medya, oyun ve video uygulamalarında geçirdiğin süreyi görmek için '
          'Android\'in "Kullanım erişimi" iznini vermelisin. Veriler telefonundan çıkmaz.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              step('1', 'Aşağıdaki butona bas, "Kullanım erişimi" ayarı açılacak.'),
              step('2', 'Listede "Günlük" uygulamasını bul.'),
              step('3', '"Kullanım erişimine izin ver" anahtarını aç ve geri dön.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: ScreenTime.openSettings,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('İzin ver'),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final apps = _apps;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Bugün')),
              ButtonSegment(value: 1, label: Text('Dün')),
              ButtonSegment(value: 2, label: Text('Son 7 gün')),
            ],
            selected: {_range},
            onSelectionChanged: (s) {
              setState(() => _range = s.first);
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (apps == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            _summaryCard(context, apps),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _groupTile(context, apps, AppGroup.social)),
                const SizedBox(width: 10),
                Expanded(child: _groupTile(context, apps, AppGroup.game)),
              ],
            ),
            const SizedBox(height: 24),
            const SectionLabel('Son 7 gün'),
            const SizedBox(height: 8),
            _dailyChart(context),
            const SizedBox(height: 24),
            SectionLabel('Uygulamalar',
                trailing: Text('${apps.length} uygulama',
                    style: TextStyle(fontSize: 12, color: muted))),
            const SizedBox(height: 8),
            if (apps.isEmpty)
              Text('Bu aralıkta kullanım kaydı yok.', style: TextStyle(color: muted))
            else
              for (final a in apps.take(25)) _appRow(context, a, apps.first.duration),
          ],
        ],
      ),
    );
  }

  Map<AppGroup, Duration> _byGroup(List<AppUsage> apps) {
    final m = <AppGroup, Duration>{};
    for (final a in apps) {
      m[a.group] = (m[a.group] ?? Duration.zero) + a.duration;
    }
    return m;
  }

  /// Çubuktaki pay (binde), en az 1.
  static int _share(Duration part, Duration total) {
    if (total.inSeconds <= 0) return 1;
    final v = part.inSeconds * 1000 ~/ total.inSeconds;
    return v < 1 ? 1 : v;
  }

  Widget _summaryCard(BuildContext context, List<AppUsage> apps) {
    final total = apps.fold(Duration.zero, (a, e) => a + e.duration);
    final groups = _byGroup(apps).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final launches = apps.fold(0, (a, e) => a + e.launches);
    final title = switch (_range) { 1 => 'DÜN', 2 => 'SON 7 GÜN', _ => 'BUGÜN' };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.redDeep, AppTheme.surface1],
        ),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$title EKRAN SÜRESİ',
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          Text(fmtUsage(total),
              style: const TextStyle(
                  fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1)),
          Text(
            _range == 2
                ? 'Günlük ortalama ${fmtUsage(total ~/ 7)} · $launches kez açıldı'
                : '$launches kez uygulama açtın',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          if (total > Duration.zero)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final g in groups)
                      Expanded(
                        flex: _share(g.value, total),
                        child: Container(color: g.key.color),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final g in groups)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: g.key.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('${g.key.label} ${fmtUsage(g.value)}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupTile(BuildContext context, List<AppUsage> apps, AppGroup group) {
    final list = apps.where((a) => a.group == group).toList();
    final total = list.fold(Duration.zero, (a, e) => a + e.duration);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: group.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: group.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${group.emoji} ${group.label}', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 4),
          Text(fmtUsage(total),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: group.color)),
          const SizedBox(height: 2),
          Text(
            list.isEmpty ? 'Kullanım yok 👏' : 'En çok: ${list.first.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _dailyChart(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final peak = _daily.fold(Duration.zero, (a, e) => e > a ? e : a);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _daily.length; i++)
              Expanded(
                child: Builder(builder: (_) {
                  final d = DateTime(today.year, today.month, today.day - (6 - i));
                  final v = _daily[i];
                  final isToday = i == _daily.length - 1;
                  final h = peak == Duration.zero ? 0.0 : v.inSeconds / peak.inSeconds;
                  return Column(
                    children: [
                      Text(v.inMinutes == 0 ? '' : '${(v.inMinutes / 60).toStringAsFixed(1)}s',
                          style: TextStyle(fontSize: 10, color: muted)),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: h < 0.03 ? 0.03 : h,
                            child: Container(
                              width: 18,
                              decoration: BoxDecoration(
                                color: isToday ? AppTheme.redBright : AppTheme.red.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(trWeekdaysShort[d.weekday - 1],
                          style: TextStyle(
                              fontSize: 11,
                              color: isToday ? Colors.white : muted,
                              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
                    ],
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _appRow(BuildContext context, AppUsage a, Duration max) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final ratio = max == Duration.zero ? 0.0 : a.duration.inSeconds / max.inSeconds;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: a.group.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              a.label.isEmpty ? '?' : a.label.substring(0, 1).toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: a.group.color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(a.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(fmtUsage(a.duration),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: AppTheme.surface3,
                    color: a.group.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${a.group.emoji} ${a.group.label} · ${a.launches} kez açıldı',
                    style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
