import 'package:flutter/material.dart';

import '../categories.dart' show trLower;
import '../game.dart';
import '../health_data.dart';
import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../trackers.dart';
import '../widgets.dart';

const _green = Color(0xFF66BB6A);
const _blue = Color(0xFF4DA3FF);

/// Profildeki özet kart: bugünkü adım ve dün geceki uyku.
class HealthCard extends StatelessWidget {
  const HealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final h = HealthData.instance;
    final today = h.day(DateTime.now());
    final connected = h.connected;
    return Material(
      color: AppTheme.surface1,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => const HealthPage())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const Text('❤️', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected && today?.steps != null
                          ? 'Bugün ${fmtSteps(today!.steps!)} adım'
                          : 'Adım, uyku ve egzersiz',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connected
                          ? (today?.sleep == null
                              ? 'Dün gece uyku verisi yok'
                              : '😴 Dün gece ${fmtDuration(today!.sleep!.inMinutes)} uyudun')
                          : 'Health Connect\'e bağlan, saatinin verisi de gelsin',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Health Connect verileri: adım, uyku, egzersiz ve takiplerle karşılaştırma.
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> with WidgetsBindingObserver {
  final h = HealthData.instance;
  HealthStatus? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(force: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Health Connect'i yükleyip / izin verip geri dönünce yeniden dene.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load({bool force = false}) async {
    final s = await h.status();
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = s == HealthStatus.ready;
    });
    if (s != HealthStatus.ready) return;
    await h.checkConnected();
    if (h.connected) await h.refresh(force: force);
    Game.instance.changes.value++;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connect() async {
    setState(() => _loading = true);
    final ok = await h.connect();
    Game.instance.changes.value++;
    if (!mounted) return;
    setState(() => _loading = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('İzin verilmedi. Health Connect ayarlarından "Günlük"e izin verebilirsin.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_status) {
      null => const Center(child: CircularProgressIndicator()),
      HealthStatus.unsupported =>
        _message(context, '📱', 'Sağlık verileri sadece Android telefonda çalışır.'),
      HealthStatus.notInstalled || HealthStatus.needsUpdate => _install(context),
      HealthStatus.ready => h.connected ? _content(context) : _connectView(context),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('❤️ Sağlık')),
      body: body,
    );
  }

  Widget _message(BuildContext context, String emoji, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _install(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('🩺', style: TextStyle(fontSize: 56), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          _status == HealthStatus.needsUpdate
              ? 'Health Connect güncellenmeli'
              : 'Health Connect gerekli',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Adım, uyku ve egzersiz verileri Google\'ın Health Connect uygulamasından okunur. '
          'Android 14 ve üstünde telefonda hazır gelir; daha eskilerde Play Store\'dan yüklenir.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: h.install,
          icon: const Icon(Icons.download_rounded),
          label: Text(_status == HealthStatus.needsUpdate ? 'Güncelle' : 'Health Connect\'i yükle'),
        ),
      ],
    );
  }

  Widget _connectView(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget row(String emoji, String title, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(text, style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('❤️', style: TextStyle(fontSize: 56), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('Sağlık verilerini bağla',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Telefonun, akıllı saatin ya da bilekliğin Health Connect\'e yazdığı veriler '
          'otomatik gelir. Sadece okunur, hiçbir şey değiştirilmez ve telefondan çıkmaz.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              row('🚶', 'Adım görevi', '"Bugün 8.000 adım at" kendiliğinden kontrol edilir, +XP'),
              row('😴', 'Gerçek uyku', 'Görevlerde profildeki yatma saati yerine gerçek saat'),
              row('🏋️', 'Egzersizler', 'Saatte kaydettiğin antrenmanlar görev sayılır'),
              row('📊', 'Karşılaştırma', 'Sigarasız günlerde kaç adım daha fazla attığın'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _loading ? null : _connect,
          icon: const Icon(Icons.link_rounded),
          label: const Text('Health Connect\'e bağlan'),
        ),
      ],
    );
  }

  Widget _hint(BuildContext context, String emoji, String title, String text, String action,
      VoidCallback onTap) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _loading ? null : onTap, child: Text(action)),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final todayData = h.day(today);
    final avg = h.averageSteps(today);
    var target = avg == null ? 8000 : ((avg * 1.1) / 500).round() * 500;
    if (target < 5000) target = 5000;
    if (target > 15000) target = 15000;
    final (bed, realBed) = Game.instance.bedtime;
    final workouts = [
      for (final d in days.reversed) ...?h.day(d)?.workouts,
    ];

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (h.missing.isNotEmpty) ...[
            _hint(context, '🔒', '${h.missing.join(', ')} için izin kapalı',
                'Health Connect\'te "Günlük" uygulamasına bu verileri okuma izni ver.',
                'İzin ver', _connect),
            const SizedBox(height: 12),
          ] else if (!_loading && h.noData) ...[
            _hint(
                context,
                '⏳',
                'Health Connect\'te henüz veri yok',
                'Saatinin uygulaması (Mi Fitness, Samsung Health, Google Fit…) verileri '
                    'Health Connect\'e yazınca burada görünür. O uygulamayı açıp senkronize et, '
                    'sonra aşağı çekip yenile. Health Connect > Veri ve erişim bölümünde '
                    'adımların görünüyorsa burada da görünür.',
                'Yenile',
                () => _load(force: true)),
            const SizedBox(height: 12),
          ],
          _stepsCard(context, todayData?.steps ?? 0, target, avg),
          const SizedBox(height: 24),
          const SectionLabel('Adımlar · son 7 gün'),
          const SizedBox(height: 8),
          _bars(context, days, [for (final d in days) (h.day(d)?.steps ?? 0).toDouble()],
              _green, (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}b' : '${v.round()}'),
          const SizedBox(height: 24),
          const SectionLabel('Uyku · son 7 gece'),
          const SizedBox(height: 8),
          _sleepSummary(context, todayData, bed, realBed),
          const SizedBox(height: 8),
          _bars(context, days,
              [for (final d in days) (h.day(d)?.sleep?.inMinutes ?? 0) / 60], _blue,
              (v) => v == 0 ? '' : '${v.toStringAsFixed(1)}s'),
          const SizedBox(height: 24),
          const SectionLabel('Egzersizler · son 7 gün'),
          const SizedBox(height: 8),
          if (workouts.isEmpty)
            Text('Kayıtlı egzersiz yok. Saatinde ya da spor uygulamanda başlattığın '
                'antrenmanlar burada görünür.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          else
            for (final w in workouts) _workoutRow(context, w),
          for (final t in Store.instance.trackers) ...[
            const SizedBox(height: 24),
            SectionLabel('${t.name} ve adımların · son 30 gün'),
            const SizedBox(height: 8),
            _compareCard(context, t, today),
          ],
        ],
      ),
    );
  }

  Widget _stepsCard(BuildContext context, int steps, int target, int? avg) {
    final p = target == 0 ? 0.0 : steps / target;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_green.withValues(alpha: 0.30), AppTheme.surface1],
        ),
        border: Border.all(color: _green.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: CustomPaint(
              painter: RingPainter(p > 1 ? 1 : p, stroke: 12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🚶', style: TextStyle(fontSize: 22)),
                    Text('${(p * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BUGÜN',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                Text(fmtSteps(steps),
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1)),
                Text('Hedef ${fmtSteps(target)} adım',
                    style: const TextStyle(color: Colors.white70)),
                if (avg != null)
                  Text('7 gün ortalaması ${fmtSteps(avg)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                if (steps >= target)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('🎉 Hedefe ulaştın!',
                        style: TextStyle(color: _green, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sleepSummary(BuildContext context, DayHealth? today, int bed, bool realBed) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final avg = h.averageSleep();
    final s = today?.sleep;
    final from = today?.sleepStart;
    final to = today?.sleepEnd;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dün gece', style: TextStyle(fontSize: 12, color: muted)),
                Text(s == null ? '—' : fmtDuration(s.inMinutes),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900, color: _blue)),
                if (from != null && to != null)
                  Text(
                      '${fmtMinutes(from.hour * 60 + from.minute)} – '
                      '${fmtMinutes(to.hour * 60 + to.minute)}',
                      style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ortalama', style: TextStyle(fontSize: 12, color: muted)),
                Text(avg == null ? '—' : fmtDuration(avg.inMinutes),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(
                  realBed ? 'Gerçek yatış ~${fmtMinutes(bed)}' : 'Yatış (profil) ${fmtMinutes(bed)}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bars(BuildContext context, List<DateTime> days, List<double> values, Color color,
      String Function(double) label) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final peak = values.fold(0.0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Text(values[i] == 0 ? '' : label(values[i]),
                        style: TextStyle(fontSize: 10, color: muted)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: peak == 0 || values[i] / peak < 0.03 ? 0.03 : values[i] / peak,
                          child: Container(
                            width: 18,
                            decoration: BoxDecoration(
                              color: i == days.length - 1 ? color : color.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(trWeekdaysShort[days[i].weekday - 1],
                        style: TextStyle(
                            fontSize: 11,
                            color: i == days.length - 1 ? Colors.white : muted,
                            fontWeight: i == days.length - 1 ? FontWeight.w800 : FontWeight.w500)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _workoutRow(BuildContext context, Workout w) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
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
          const Text('🏋️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text('${fmtDate(w.start)} · ${fmtDuration(w.duration.inMinutes)}',
              style: TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    );
  }

  /// Takipsiz (ör. sigarasız) günlerle takip kaydı olan günlerin adım ortalaması.
  Widget _compareCard(BuildContext context, Tracker t, DateTime today) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    var cleanSum = 0, cleanN = 0, otherSum = 0, otherN = 0;
    for (var i = 1; i <= 30; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      final steps = h.day(d)?.steps;
      if (steps == null || steps == 0) continue;
      if (t.countOn(d) == 0) {
        cleanSum += steps;
        cleanN++;
      } else {
        otherSum += steps;
        otherN++;
      }
    }
    final clean = cleanN == 0 ? null : cleanSum ~/ cleanN;
    final other = otherN == 0 ? null : otherSum ~/ otherN;
    final name = trLower(t.name);
    String text;
    if (clean == null || other == null) {
      text = 'Karşılaştırma için hem $name olan hem olmayan günlerde adım verisi gerekiyor.';
    } else if (clean > other) {
      text = '${t.emoji} ${_cap(name)}${_without(name)} günlerde ortalama '
          '${fmtSteps(clean - other)} adım daha fazla attın.';
    } else if (other > clean) {
      text = '${t.emoji} ${_cap(name)} olan günlerde ${fmtSteps(other - clean)} adım daha fazla '
          'attın; burada bir bağlantı görünmüyor.';
    } else {
      text = 'İki tür günde de adımların aynı.';
    }
    Widget cell(String label, int? v, int n, Color c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: muted)),
              Text(v == null ? '—' : fmtSteps(v),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
              Text('$n gün', style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              cell('${t.emoji} yok', clean, cleanN, _green),
              cell('${t.emoji} var', other, otherN, AppTheme.redBright),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  static String _cap(String s) {
    if (s.isEmpty) return s;
    final first = s[0] == 'i' ? 'İ' : (s[0] == 'ı' ? 'I' : s[0].toUpperCase());
    return first + s.substring(1);
  }

  /// Ünlü uyumuna göre "-sız/-siz/-suz/-süz": sigarasız, alkolsüz, kahvesiz.
  static String _without(String word) {
    for (var i = word.length - 1; i >= 0; i--) {
      switch (word[i]) {
        case 'a' || 'ı':
          return 'sız';
        case 'e' || 'i':
          return 'siz';
        case 'o' || 'u':
          return 'suz';
        case 'ö' || 'ü':
          return 'süz';
      }
    }
    return 'siz';
  }
}
