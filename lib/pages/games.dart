import 'dart:math';

import 'package:flutter/material.dart';

import '../game.dart';
import '../theme.dart';

/// Mini oyun tanımı: kart ve sayfa.
class MiniGame {
  const MiniGame(this.emoji, this.name, this.description, this.xpHint, this.builder);

  final String emoji;
  final String name;
  final String description;
  final String xpHint;
  final Widget Function() builder;
}

final miniGames = <MiniGame>[
  MiniGame('🫁', 'Nefes', 'Daireyle birlikte nefes al ve ver. İsteği yatıştırır.', '+15 XP',
      () => const BreathingGame()),
  MiniGame('🎈', 'Balon patlat', '30 saniyede balonları patlat, 🚬 balonlarından kaç.',
      '5–30 XP', () => const BalloonGame()),
  MiniGame('🃏', 'Hafıza kartları', 'Eşleri bul; ne kadar az hamle, o kadar çok XP.',
      '12–30 XP', () => const MemoryGame()),
];

void openGame(BuildContext context, MiniGame g) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => g.builder()));

/// "Canım çekti" penceresi: oyun seçtirir.
Future<void> showCravingGames(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('İstek geçicidir 💪',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Birkaç dakika kendini oyala, istek çoğu zaman 3-5 dakikada geçer.',
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            GameCards(onOpen: (g) {
              Navigator.pop(ctx);
              openGame(context, g);
            }),
          ],
        ),
      ),
    ),
  );
}

/// Oyun kartları listesi (profil sayfasında ve "Canım çekti" penceresinde).
class GameCards extends StatelessWidget {
  const GameCards({super.key, this.onOpen});

  final void Function(MiniGame)? onOpen;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        for (final g in miniGames)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppTheme.surface1,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onOpen != null ? onOpen!(g) : openGame(context, g),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.surface3,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(g.emoji, style: const TextStyle(fontSize: 26)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(g.description, style: TextStyle(fontSize: 12, color: muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(g.xpHint,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.redBright)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Oyun bitince XP verir ve sonucu gösterir.
Future<void> _finish(BuildContext context, String game, int xp, String message) async {
  final given = await Game.instance.awardGame(game, xp);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(given > 0 ? '+$given XP 🎉' : 'Oyun bitti'),
      content: Text(given > 0
          ? message
          : '$message\n\nBugünkü oyun XP sınırına ($dailyGameXpCap) ulaştın, yarın yine kazanabilirsin.'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.pop(context);
          },
          child: const Text('Çık'),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tekrar')),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Nefes: 4 sn al · 4 sn tut · 6 sn ver, 5 tur.
// ---------------------------------------------------------------------------

class BreathingGame extends StatefulWidget {
  const BreathingGame({super.key});

  @override
  State<BreathingGame> createState() => _BreathingGameState();
}

class _BreathingGameState extends State<BreathingGame> with SingleTickerProviderStateMixin {
  static const _rounds = 5;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));
  int _round = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) async {
      if (s != AnimationStatus.completed) return;
      if (_round + 1 < _rounds) {
        setState(() => _round++);
        _c.forward(from: 0);
      } else {
        setState(() => _running = false);
        await _finish(context, 'Nefes', 15, '$_rounds tur nefes egzersizini tamamladın.');
        if (mounted) setState(() => _round = 0);
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _round = 0;
      _running = true;
    });
    _c.forward(from: 0);
  }

  /// (yazı, daire ölçeği 0..1, aşamada kalan saniye)
  (String, double, int) _phase(double v) {
    final s = v * 14;
    if (s < 4) return ('Nefes al', s / 4, (4 - s).ceil());
    if (s < 8) return ('Tut', 1, (8 - s).ceil());
    return ('Yavaşça ver', 1 - (s - 8) / 6, (14 - s).ceil());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🫁 Nefes')),
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final (label, scale, left) = _running ? _phase(_c.value) : ('Hazır mısın?', 0.0, 0);
            final size = 120 + 160 * scale;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  height: 300,
                  child: Center(
                    child: Container(
                      width: size,
                      height: size,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppTheme.redBright.withValues(alpha: 0.9),
                          AppTheme.redDeep.withValues(alpha: 0.6),
                        ]),
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.red.withValues(alpha: 0.5),
                              blurRadius: 30 + 30 * scale),
                        ],
                      ),
                      child: Text(_running ? '$left' : '',
                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_running ? 'Tur ${_round + 1} / $_rounds' : '4 sn al · 4 sn tut · 6 sn ver',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                if (!_running)
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Başla'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balon patlat: 30 sn, 🎈 +1, 🚬 −3.
// ---------------------------------------------------------------------------

class _Balloon {
  _Balloon(this.id, this.x, this.born, this.speed, this.bad);

  final int id;
  final double x; // 0..1
  final int born; // ms
  final double speed; // ekran yüksekliği / sn
  final bool bad;
}

class BalloonGame extends StatefulWidget {
  const BalloonGame({super.key});

  @override
  State<BalloonGame> createState() => _BalloonGameState();
}

class _BalloonGameState extends State<BalloonGame> with SingleTickerProviderStateMixin {
  static const _seconds = 30;
  late final AnimationController _ticker =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));
  final _rnd = Random();
  final _clock = Stopwatch();
  final _balloons = <_Balloon>[];
  int _nextId = 0;
  int _lastSpawn = 0;
  int _score = 0;
  int _popped = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _ticker.addListener(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _balloons.clear();
      _score = 0;
      _popped = 0;
      _lastSpawn = 0;
      _running = true;
    });
    _clock
      ..reset()
      ..start();
    _ticker.repeat();
  }

  void _tick() {
    final now = _clock.elapsedMilliseconds;
    if (now >= _seconds * 1000) {
      _end();
      return;
    }
    // Zaman geçtikçe daha sık ve hızlı balon.
    final every = 700 - (now ~/ 100);
    if (now - _lastSpawn > every) {
      _lastSpawn = now;
      _balloons.add(_Balloon(_nextId++, _rnd.nextDouble(), now,
          0.25 + _rnd.nextDouble() * 0.2 + now / 100000, _rnd.nextDouble() < 0.18));
    }
    _balloons.removeWhere((b) => _y(b, now) < -0.2);
    setState(() {});
  }

  double _y(_Balloon b, int now) => 1.05 - (now - b.born) / 1000 * b.speed;

  void _pop(_Balloon b) {
    setState(() {
      _balloons.remove(b);
      if (b.bad) {
        _score = max(0, _score - 3);
      } else {
        _score++;
        _popped++;
      }
    });
  }

  Future<void> _end() async {
    _ticker.stop();
    _clock.stop();
    setState(() => _running = false);
    final xp = (5 + _score ~/ 2).clamp(5, 30);
    await _finish(context, 'Balon patlat', xp, '$_popped balon patlattın, puanın $_score.');
  }

  @override
  Widget build(BuildContext context) {
    final left = _running ? _seconds - _clock.elapsedMilliseconds ~/ 1000 : _seconds;
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎈 Balon patlat'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('⏱ $left sn   ⭐ $_score',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final now = _clock.elapsedMilliseconds;
        return Stack(
          children: [
            for (final b in _balloons)
              Positioned(
                left: b.x * (box.maxWidth - 64),
                top: _y(b, now) * box.maxHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _pop(b),
                  child: SizedBox(
                    width: 64,
                    height: 72,
                    child: Center(
                      child: Text(b.bad ? '🚬' : '🎈', style: const TextStyle(fontSize: 46)),
                    ),
                  ),
                ),
              ),
            if (!_running)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎈 +1   ·   🚬 −3', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Başla'),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Hafıza kartları: 8 çift.
// ---------------------------------------------------------------------------

class MemoryGame extends StatefulWidget {
  const MemoryGame({super.key});

  @override
  State<MemoryGame> createState() => _MemoryGameState();
}

class _MemoryGameState extends State<MemoryGame> {
  static const _faces = ['🍎', '🌙', '⭐', '🎧', '🌿', '🚲', '📚', '💧'];
  late List<String> _cards;
  final _open = <int>{};
  final _matched = <int>{};
  int? _first;
  bool _lock = false;
  int _moves = 0;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _cards = [..._faces, ..._faces]..shuffle();
    _open.clear();
    _matched.clear();
    _first = null;
    _lock = false;
    _moves = 0;
  }

  Future<void> _tap(int i) async {
    if (_lock || _open.contains(i) || _matched.contains(i)) return;
    setState(() => _open.add(i));
    if (_first == null) {
      _first = i;
      return;
    }
    final a = _first!;
    _first = null;
    _moves++;
    if (_cards[a] == _cards[i]) {
      setState(() => _matched.addAll([a, i]));
      if (_matched.length == _cards.length) {
        final xp = _moves <= 10
            ? 30
            : _moves <= 14
                ? 25
                : _moves <= 20
                    ? 18
                    : 12;
        await _finish(context, 'Hafıza kartları', xp, '$_moves hamlede bitirdin.');
        if (mounted) setState(_reset);
      }
    } else {
      _lock = true;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() {
        _open.removeAll([a, i]);
        _lock = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🃏 Hafıza kartları'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('Hamle: $_moves',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            shrinkWrap: true,
            children: [
              for (var i = 0; i < _cards.length; i++)
                GestureDetector(
                  onTap: () => _tap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _matched.contains(i)
                          ? AppTheme.red.withValues(alpha: 0.25)
                          : _open.contains(i)
                              ? AppTheme.surface3
                              : AppTheme.surface2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _matched.contains(i) ? AppTheme.red : AppTheme.border),
                    ),
                    child: Text(
                      _open.contains(i) || _matched.contains(i) ? _cards[i] : '?',
                      style: TextStyle(
                          fontSize: 30,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
