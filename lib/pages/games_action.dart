import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'games.dart' show finishGame;

/// [v]'yi [lo]..[hi] aralığına sıkıştırır (int kalır).
int _xp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Oyunun üstündeki başlık çubuğu: sağda süre / puan.
PreferredSizeWidget _bar(String title, String right) => AppBar(
      title: Text(title),
      actions: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ],
    );

/// Başlamadan önceki ekran: kurallar + Başla.
Widget _startOverlay(String rules, VoidCallback onStart) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rules, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Başla'),
            ),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Engelden kaç: parmağınla karakteri sağa sola sürükle, düşenlerden kaç,
// yıldızları topla. 3 can, en fazla 60 sn.
// ---------------------------------------------------------------------------

class _Drop {
  _Drop(this.x, this.born, this.speed, this.kind);

  final double x; // 0..1
  final int born; // ms
  final double speed; // ekran yüksekliği / sn
  final int kind; // 0 engel, 1 yıldız, 2 can
}

class DodgeGame extends StatefulWidget {
  const DodgeGame({super.key});

  @override
  State<DodgeGame> createState() => _DodgeGameState();
}

class _DodgeGameState extends State<DodgeGame> with SingleTickerProviderStateMixin {
  static const _seconds = 60;
  static const _dropSize = 48.0;
  static const _playerSize = 64.0;
  static const _obstacles = ['☄️', '🚬', '🪨'];
  late final AnimationController _ticker =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));
  final _rnd = Random();
  final _clock = Stopwatch();
  final _drops = <_Drop>[];
  final _faces = <_Drop, String>{};
  double _player = 0.5; // 0..1
  double _w = 0, _h = 0;
  int _lastSpawn = 0;
  int _lives = 3;
  int _stars = 0;
  int _hitAt = -1000;
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
      _drops.clear();
      _faces.clear();
      _player = 0.5;
      _lastSpawn = 0;
      _lives = 3;
      _stars = 0;
      _hitAt = -1000;
      _running = true;
    });
    _clock
      ..reset()
      ..start();
    _ticker.repeat();
  }

  int get _score => _clock.elapsedMilliseconds ~/ 1000 + _stars * 3;

  double _y(_Drop d, int now) => (now - d.born) / 1000 * d.speed - 0.08;

  void _tick() {
    if (_w == 0) return;
    final now = _clock.elapsedMilliseconds;
    if (now >= _seconds * 1000) {
      _end();
      return;
    }
    // Zaman geçtikçe daha sık ve hızlı.
    final every = 650 - now ~/ 120;
    if (now - _lastSpawn > (every < 220 ? 220 : every)) {
      _lastSpawn = now;
      final r = _rnd.nextDouble();
      final kind = r < 0.03 ? 2 : (r < 0.2 ? 1 : 0);
      final d = _Drop(_rnd.nextDouble(), now, 0.35 + _rnd.nextDouble() * 0.25 + now / 90000, kind);
      _drops.add(d);
      _faces[d] = switch (kind) {
        1 => '⭐',
        2 => '❤️',
        _ => _obstacles[_rnd.nextInt(_obstacles.length)],
      };
    }
    // Çarpışma: düşenin ortası karakterin kutusuna girdi mi?
    final playerLeft = _player * (_w - _playerSize);
    final playerTop = _h - _playerSize - 24;
    final hit = <_Drop>[];
    for (final d in _drops) {
      final cx = d.x * (_w - _dropSize) + _dropSize / 2;
      final cy = _y(d, now) * _h + _dropSize / 2;
      if (cx > playerLeft + 6 &&
          cx < playerLeft + _playerSize - 6 &&
          cy > playerTop + 8 &&
          cy < playerTop + _playerSize) {
        hit.add(d);
      }
    }
    for (final d in hit) {
      _drops.remove(d);
      _faces.remove(d);
      switch (d.kind) {
        case 1:
          _stars++;
        case 2:
          if (_lives < 3) _lives++;
        default:
          _lives--;
          _hitAt = now;
      }
    }
    _drops.removeWhere((d) {
      final gone = _y(d, now) > 1.1;
      if (gone) _faces.remove(d);
      return gone;
    });
    if (_lives <= 0) {
      _end();
      return;
    }
    setState(() {});
  }

  Future<void> _end() async {
    if (!_running) return;
    _ticker.stop();
    _clock.stop();
    setState(() => _running = false);
    final secs = _clock.elapsedMilliseconds ~/ 1000;
    final xp = _xp(5 + _score ~/ 3, 5, 30);
    await finishGame(context, 'Engelden kaç', xp,
        '$secs saniye dayandın, $_stars yıldız topladın. Puanın $_score.');
  }

  @override
  Widget build(BuildContext context) {
    final now = _clock.elapsedMilliseconds;
    final left = _running ? _seconds - now ~/ 1000 : _seconds;
    final flash = _running && now - _hitAt < 250;
    return Scaffold(
      appBar: _bar('🌠 Engelden kaç', '${'❤️' * (_lives < 0 ? 0 : _lives)}  ⏱ $left  ⭐ $_score'),
      body: LayoutBuilder(builder: (context, box) {
        _w = box.maxWidth;
        _h = box.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            if (!_running) return;
            final v = _player + d.delta.dx / (_w - _playerSize);
            _player = v < 0 ? 0 : (v > 1 ? 1 : v);
          },
          child: Stack(
            children: [
              if (flash) Positioned.fill(child: Container(color: Colors.red.withValues(alpha: 0.18))),
              for (final d in _drops)
                Positioned(
                  left: d.x * (_w - _dropSize),
                  top: _y(d, now) * _h,
                  child: SizedBox(
                    width: _dropSize,
                    height: _dropSize,
                    child: Center(
                        child: Text(_faces[d] ?? '☄️', style: const TextStyle(fontSize: 36))),
                  ),
                ),
              Positioned(
                left: _player * (_w - _playerSize),
                top: _h - _playerSize - 24,
                child: SizedBox(
                  width: _playerSize,
                  height: _playerSize,
                  child: const Center(child: Text('🏃', style: TextStyle(fontSize: 48))),
                ),
              ),
              if (!_running)
                _startOverlay(
                    'Parmağını sürükleyerek kaç!\n☄️ 🚬 🪨 −1 can   ·   ⭐ +3   ·   ❤️ +1 can',
                    _start),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Hedef vur: beliren hedeflere küçülüp kaybolmadan dokun. Seri yaptıkça çarpan
// artar; 💣'ye dokunma. 30 sn.
// ---------------------------------------------------------------------------

class _Target {
  _Target(this.x, this.y, this.born, this.life, this.bomb);

  final double x, y; // 0..1
  final int born, life; // ms
  final bool bomb;
}

class TargetGame extends StatefulWidget {
  const TargetGame({super.key});

  @override
  State<TargetGame> createState() => _TargetGameState();
}

class _TargetGameState extends State<TargetGame> with SingleTickerProviderStateMixin {
  static const _seconds = 30;
  static const _size = 76.0;
  late final AnimationController _ticker =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));
  final _rnd = Random();
  final _clock = Stopwatch();
  final _targets = <_Target>[];
  int _lastSpawn = 0;
  int _score = 0;
  int _combo = 0;
  int _best = 0;
  int _hits = 0;
  String? _pop; // son vuruşun yazısı (+3 x2 gibi)
  int _popAt = -1000;
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
      _targets.clear();
      _lastSpawn = 0;
      _score = 0;
      _combo = 0;
      _best = 0;
      _hits = 0;
      _pop = null;
      _running = true;
    });
    _clock
      ..reset()
      ..start();
    _ticker.repeat();
  }

  int get _multiplier => 1 + _combo ~/ 5; // her 5 seride çarpan +1

  void _tick() {
    final now = _clock.elapsedMilliseconds;
    if (now >= _seconds * 1000) {
      _end();
      return;
    }
    final every = 800 - now ~/ 60; // 800 ms -> 300 ms
    if (now - _lastSpawn > (every < 300 ? 300 : every) && _targets.length < 5) {
      _lastSpawn = now;
      final life = 1500 - now ~/ 40; // 1500 ms -> 750 ms
      _targets.add(_Target(_rnd.nextDouble(), _rnd.nextDouble(), now, life < 750 ? 750 : life,
          _rnd.nextDouble() < 0.15));
    }
    // Kaçırılan (bomba olmayan) hedef seriyi bozar.
    final missed = _targets.where((t) => now - t.born > t.life).toList();
    for (final t in missed) {
      _targets.remove(t);
      if (!t.bomb) _combo = 0;
    }
    setState(() {});
  }

  void _hit(_Target t) {
    if (!_running) return;
    final now = _clock.elapsedMilliseconds;
    setState(() {
      _targets.remove(t);
      if (t.bomb) {
        _score = max(0, _score - 5);
        _combo = 0;
        _pop = '💥 −5';
      } else {
        // Hızlı vuruş (ömrünün ilk yarısı) 2 puan, sonra 1.
        final fast = now - t.born < t.life / 2;
        final pts = (fast ? 2 : 1) * _multiplier;
        _score += pts;
        _combo++;
        _hits++;
        if (_combo > _best) _best = _combo;
        _pop = '+$pts${_multiplier > 1 ? '  x$_multiplier' : ''}';
      }
      _popAt = now;
    });
  }

  Future<void> _end() async {
    if (!_running) return;
    _ticker.stop();
    _clock.stop();
    setState(() {
      _running = false;
      _targets.clear();
    });
    final xp = _xp(5 + _score ~/ 3, 5, 30);
    await finishGame(context, 'Hedef vur', xp,
        '$_hits hedef vurdun, en uzun serin $_best. Puanın $_score.');
  }

  @override
  Widget build(BuildContext context) {
    final now = _clock.elapsedMilliseconds;
    final left = _running ? _seconds - now ~/ 1000 : _seconds;
    return Scaffold(
      appBar: _bar('🎯 Hedef vur', '⏱ $left  ⭐ $_score'),
      body: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth - _size;
        final h = box.maxHeight - _size - 40;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Boşa dokunmak seriyi bozar.
          onTapDown: (_) {
            if (_running && _combo > 0) setState(() => _combo = 0);
          },
          child: Stack(
            children: [
              if (_running)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 8,
                  child: Text(
                    _combo >= 5 ? '🔥 Seri $_combo  ·  x$_multiplier' : 'Seri $_combo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _combo >= 5
                            ? AppTheme.redBright
                            : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final t in _targets)
                Positioned(
                  left: t.x * w,
                  top: 40 + t.y * h,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _hit(t),
                    child: SizedBox(
                      width: _size,
                      height: _size,
                      child: Center(
                        child: Transform.scale(
                          // Ömrü bittikçe küçülür.
                          scale: 1 - min(1.0, max(0.0, (now - t.born) / t.life)) * 0.6,
                          child: Text(t.bomb ? '💣' : '🎯', style: const TextStyle(fontSize: 56)),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_pop != null && now - _popAt < 500)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Text(_pop!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                ),
              if (!_running)
                _startOverlay('Hedefler küçülüp kaybolmadan dokun!\n'
                    'Hızlı vur = 2 puan · 5 seride çarpan artar\n💣 −5 ve seri biter', _start),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Zıpla koş: dokununca zıpla, 🌵'lerin üstünden atla, 🦅'nın altından geç,
// 🪙 topla. Hız giderek artar; ilk çarpmada biter.
// ---------------------------------------------------------------------------

class _Thing {
  _Thing(this.x, this.kind);

  double x; // px, sol kenar
  final int kind; // 0 kaktüs, 1 kuş, 2 altın
}

class RunnerGame extends StatefulWidget {
  const RunnerGame({super.key});

  @override
  State<RunnerGame> createState() => _RunnerGameState();
}

class _RunnerGameState extends State<RunnerGame> with SingleTickerProviderStateMixin {
  static const _player = 48.0;
  static const _gravity = 2600.0; // px/sn²
  static const _jump = 900.0; // px/sn -> en fazla ~155 px yükselir
  late final AnimationController _ticker =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));
  final _rnd = Random();
  final _clock = Stopwatch();
  final _things = <_Thing>[];
  double _w = 0, _h = 0;
  double _y = 0, _vy = 0; // yerden yükseklik, dikey hız
  double _distance = 0;
  int _coins = 0;
  int _last = 0;
  int _nextSpawn = 0;
  bool _running = false;
  bool _over = false;

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
      _things.clear();
      _y = 0;
      _vy = 0;
      _distance = 0;
      _coins = 0;
      _last = 0;
      _nextSpawn = 800;
      _running = true;
      _over = false;
    });
    _clock
      ..reset()
      ..start();
    _ticker.repeat();
  }

  int get _score => _distance ~/ 100 + _coins * 5;

  double get _speed => 300 + _clock.elapsedMilliseconds / 1000 * 10; // px/sn

  double get _ground => _h * 0.72;

  void _jumpNow() {
    if (!_running) return;
    if (_y <= 0.5) _vy = _jump;
  }

  void _tick() {
    if (_w == 0) return;
    final now = _clock.elapsedMilliseconds;
    var dt = (now - _last) / 1000;
    if (dt > 0.05) dt = 0.05;
    _last = now;

    // Zıplama fiziği.
    _vy -= _gravity * dt;
    _y += _vy * dt;
    if (_y < 0) {
      _y = 0;
      _vy = 0;
    }

    final speed = _speed;
    _distance += speed * dt;
    for (final t in _things) {
      t.x -= speed * dt;
    }
    _things.removeWhere((t) => t.x < -60);

    if (now >= _nextSpawn) {
      final r = _rnd.nextDouble();
      // Kuşlar 10. saniyeden sonra çıkar.
      final kind = r < 0.2 ? 2 : (r < 0.42 && now > 10000 ? 1 : 0);
      _things.add(_Thing(_w + 10, kind));
      // Bazen arka arkaya iki kaktüs.
      if (kind == 0 && _rnd.nextDouble() < 0.2 && now > 15000) _things.add(_Thing(_w + 50, 0));
      final gap = 1500 - now ~/ 60; // 1500 ms -> 700 ms
      _nextSpawn = now + (gap < 700 ? 700 : gap) + _rnd.nextInt(500);
    }

    // Çarpışma (kutular, biraz pay bırakarak).
    const px = 60.0;
    final hit = <_Thing>[];
    for (final t in _things) {
      final (bottom, size) = switch (t.kind) {
        0 => (0.0, 40.0),
        1 => (70.0, 40.0),
        _ => (110.0, 34.0),
      };
      final overlapX = t.x < px + _player - 10 && t.x + size > px + 10;
      final overlapY = _y < bottom + size - 6 && _y + _player > bottom + 6;
      if (overlapX && overlapY) hit.add(t);
    }
    for (final t in hit) {
      if (t.kind == 2) {
        _things.remove(t);
        _coins++;
      } else {
        _end();
        return;
      }
    }
    setState(() {});
  }

  Future<void> _end() async {
    if (!_running) return;
    _ticker.stop();
    _clock.stop();
    setState(() {
      _running = false;
      _over = true;
    });
    final xp = _xp(5 + _score ~/ 4, 5, 30);
    await finishGame(context, 'Zıpla koş', xp,
        '${(_distance / 100).round()} m koştun, $_coins altın topladın. Puanın $_score.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _bar('🏃 Zıpla koş', '🪙 $_coins  ⭐ $_score'),
      body: LayoutBuilder(builder: (context, box) {
        _w = box.maxWidth;
        _h = box.maxHeight;
        final ground = _ground;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _jumpNow(),
          child: Stack(
            children: [
              // Zemin
              Positioned(
                left: 0,
                right: 0,
                top: ground,
                child: Container(height: 3, color: AppTheme.border),
              ),
              for (final t in _things)
                Positioned(
                  left: t.x,
                  top: ground -
                      switch (t.kind) {
                        0 => 40.0,
                        1 => 110.0,
                        _ => 144.0,
                      },
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Text(
                        switch (t.kind) {
                          0 => '🌵',
                          1 => '🦅',
                          _ => '🪙',
                        },
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 60,
                top: ground - _player - _y,
                child: const SizedBox(
                  width: _player,
                  height: _player,
                  child: Center(
                    child: Transform.flip(
                      flipX: true,
                      child: Text('🏃', style: TextStyle(fontSize: 40)),
                     ),
                    ),
                  ),
              ),
              if (!_running)
                _startOverlay(
                    _over
                        ? 'Çarptın! 💥\nTekrar dene'
                        : 'Ekrana dokun = zıpla\n🌵 üstünden atla · 🦅 altından geç · 🪙 topla',
                    _start),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Refleks: ekran yeşile dönünce olabildiğince hızlı dokun. 5 tur.
// ---------------------------------------------------------------------------

enum _RState { ready, wait, go, early, shown }

class ReactionGame extends StatefulWidget {
  const ReactionGame({super.key});

  @override
  State<ReactionGame> createState() => _ReactionGameState();
}

class _ReactionGameState extends State<ReactionGame> {
  static const _rounds = 5;
  final _rnd = Random();
  final _watch = Stopwatch();
  final _times = <int>[];
  _RState _state = _RState.ready;
  Timer? _timer;
  int? _lastMs;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    setState(() => _state = _RState.wait);
    _timer = Timer(Duration(milliseconds: 1500 + _rnd.nextInt(2500)), () {
      if (!mounted) return;
      _watch
        ..reset()
        ..start();
      setState(() => _state = _RState.go);
    });
  }

  Future<void> _tap() async {
    switch (_state) {
      case _RState.ready || _RState.early || _RState.shown:
        _arm();
      case _RState.wait:
        _timer?.cancel();
        setState(() => _state = _RState.early);
      case _RState.go:
        _watch.stop();
        final ms = _watch.elapsedMilliseconds;
        setState(() {
          _times.add(ms);
          _lastMs = ms;
          _state = _RState.shown;
        });
        if (_times.length >= _rounds) {
          final avg = _times.reduce((a, b) => a + b) ~/ _times.length;
          final best = _times.reduce(min);
          final xp = avg < 250
              ? 25
              : avg < 320
                  ? 20
                  : avg < 420
                      ? 15
                      : 10;
          await finishGame(context, 'Refleks', xp, 'Ortalama $avg ms, en iyi $best ms.');
          if (mounted) {
            setState(() {
              _times.clear();
              _lastMs = null;
              _state = _RState.ready;
            });
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (Color color, String text) = switch (_state) {
      _RState.ready => (AppTheme.surface2, 'Başlamak için dokun\n\nEkran yeşil olunca hemen dokun!'),
      _RState.wait => (const Color(0xFFB71C1C), 'Bekle…'),
      _RState.go => (const Color(0xFF2E7D32), 'DOKUN!'),
      _RState.early => (AppTheme.surface2, 'Çok erken! 😅\n\nTekrar için dokun'),
      _RState.shown => (AppTheme.surface2, '$_lastMs ms\n\nDevam için dokun'),
    };
    return Scaffold(
      appBar: _bar('⚡ Refleks', 'Tur ${_times.length}/$_rounds'),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _tap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: color,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _state == _RState.go ? 48 : 24,
              fontWeight: FontWeight.w900,
              color: _state == _RState.wait || _state == _RState.go ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }
}
