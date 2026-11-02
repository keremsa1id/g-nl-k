import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../trackers.dart';

/// Sigara takibi mi (akciğer kartı gösterilir)?
bool isSmokingTracker(Tracker t) {
  final s = '${t.name} ${t.unit}'.toLowerCase();
  return t.emoji == '🚬' || s.contains('sigara') || s.contains('tütün') || s.contains('puro');
}

/// Her sigara kirlilik ekler, kirlilik [_halfLife] saatte yarıya iner.
const _perSmoke = 0.18;
const _halfLife = 18.0; // saat

double _load(List<DateTime> events, DateTime now) {
  var sum = 0.0;
  for (var i = events.length - 1; i >= 0; i--) {
    final h = now.difference(events[i]).inMinutes / 60;
    if (h < 0) continue;
    if (h > 24 * 14) break; // daha eskisinin etkisi kalmadı (liste sıralı)
    sum += _perSmoke * pow(0.5, h / _halfLife);
  }
  return sum;
}

/// 0 = tertemiz, 1 = katran dolu.
double lungDirt(List<DateTime> events, DateTime now) => 1 - exp(-_load(events, now));

/// Hiç içilmezse kirliliğin %5'in altına inmesine kalan süre.
Duration? timeToClean(List<DateTime> events, DateTime now) {
  final load = _load(events, now);
  const target = 0.0513; // 1 - e^-x = %5
  if (load <= target) return null;
  final hours = _halfLife * log(load / target) / ln2;
  return Duration(minutes: (hours * 60).round());
}

/// Sigara sayfasının üst kısmı: nefes alan büyük akciğer, durumu ve altında [counter]
/// (sayaç). İçtikçe kararır, içmedikçe temizlenir.
class LungsHero extends StatefulWidget {
  const LungsHero({super.key, required this.tracker, required this.counter});

  final Tracker tracker;
  final Widget counter;

  @override
  State<LungsHero> createState() => _LungsHeroState();
}

class _LungsHeroState extends State<LungsHero> with SingleTickerProviderStateMixin {
  // Nefes alıp verme: 4 sn'de bir genişler / daralır.
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  static (String, Color) _status(double d) => switch (d) {
        < 0.05 => ('Tertemiz 🌿', const Color(0xFF66BB6A)),
        < 0.25 => ('Hafif is var', const Color(0xFFFFCA28)),
        < 0.5 => ('Kirleniyor', const Color(0xFFFF9800)),
        < 0.75 => ('Çok kirli', const Color(0xFFFF5722)),
        _ => ('Katran dolu', const Color(0xFFE53935)),
      };

  static String _fmt(Duration d) {
    if (d.inHours >= 24) {
      final h = d.inHours % 24;
      return '${d.inDays} gün${h > 0 ? ' $h sa' : ''}';
    }
    if (d.inHours >= 1) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    return '${d.inMinutes < 1 ? 1 : d.inMinutes} dk';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dirt = lungDirt(widget.tracker.events, now);
    final left = timeToClean(widget.tracker.events, now);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return TweenAnimationBuilder<double>(
      // Yeni sigarada kir yükselir, zamanla yavaşça iner.
      tween: Tween(end: dirt),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, d, _) {
        final (label, color) = _status(d);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Arka parıltı: temizken yeşilimsi, kirlendikçe kırmızı
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        color.withValues(alpha: 0.22),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CustomPaint(painter: _LungsPainter(d, _breath)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Text('🫁 $label · %${(d * 100).round()} kirli',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(height: 14),
            widget.counter,
            const SizedBox(height: 8),
            Text(
              left == null
                  ? 'Akciğerlerin temiz, içmedikçe böyle kalır 💪'
                  : 'İçmezsen ~${_fmt(left)} sonra temiz',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            Text('Temsili gösterim; gerçek iyileşme daha uzun sürer.',
                style: TextStyle(fontSize: 10, color: muted.withValues(alpha: 0.7))),
          ],
        );
      },
    );
  }
}

class _LungsPainter extends CustomPainter {
  _LungsPainter(this.dirt, this.breath) : super(repaint: breath);

  final double dirt; // 0..1
  final Animation<double> breath; // 0..1

  // Kir lekelerinin yerleri sabit kalsın diye bir kez üretilir (0..1 koordinatları).
  static final List<(double, double, double)> _specks = () {
    final r = Random(42);
    return [for (var i = 0; i < 90; i++) (r.nextDouble(), r.nextDouble(), r.nextDouble())];
  }();

  Path _leftLung(double w, double h) => Path()
    ..moveTo(w * 0.44, h * 0.24)
    ..cubicTo(w * 0.30, h * 0.16, w * 0.15, h * 0.30, w * 0.09, h * 0.56)
    ..cubicTo(w * 0.04, h * 0.80, w * 0.10, h * 0.97, w * 0.25, h * 0.95)
    ..cubicTo(w * 0.35, h * 0.94, w * 0.42, h * 0.89, w * 0.46, h * 0.81)
    ..cubicTo(w * 0.47, h * 0.62, w * 0.47, h * 0.42, w * 0.44, h * 0.24)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final b = Curves.easeInOut.transform(breath.value);

    // Nefes: ortadan biraz genişleyip daralır.
    canvas.save();
    final scale = 0.95 + 0.05 * b;
    canvas.translate(w / 2, h * 0.55);
    canvas.scale(scale, 0.97 + 0.03 * b);
    canvas.translate(-w / 2, -h * 0.55);

    final left = _leftLung(w, h);
    final mirror = Float64List.fromList(
        [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, w, 0, 0, 1]);
    final right = left.transform(mirror);
    final lungs = Path()
      ..addPath(left, Offset.zero)
      ..addPath(right, Offset.zero);
    final bounds = lungs.getBounds();

    // Soluk borusu ve bronşlar
    final airway = Paint()
      ..color = Color.lerp(const Color(0xFFF48FB1), const Color(0xFF6D4C41), dirt * 0.7)!
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.06;
    canvas.drawLine(Offset(w * 0.5, h * 0.02), Offset(w * 0.5, h * 0.24), airway);
    airway.strokeWidth = w * 0.04;
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.5, h * 0.22)
          ..quadraticBezierTo(w * 0.47, h * 0.30, w * 0.38, h * 0.36)
          ..moveTo(w * 0.5, h * 0.22)
          ..quadraticBezierTo(w * 0.53, h * 0.30, w * 0.62, h * 0.36),
        airway);

    // Sağlıklı doku: pembe
    canvas.drawPath(
      lungs,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFA4B4), Color(0xFFE35D74)],
        ).createShader(bounds),
    );

    canvas.save();
    canvas.clipPath(lungs);

    // Kir: alttan dalgalı bir katran tabakası olarak dolar…
    if (dirt > 0.003) {
      final top = bounds.bottom - dirt * bounds.height * 1.04;
      final phase = breath.value * 2 * pi;
      final wave = Path()..moveTo(bounds.left, top);
      for (var x = bounds.left; x <= bounds.right + 6; x += 5) {
        wave.lineTo(x, top + sin(x / 9 + phase) * 2.5);
      }
      wave
        ..lineTo(bounds.right, bounds.bottom)
        ..lineTo(bounds.left, bounds.bottom)
        ..close();
      canvas.drawPath(
        wave,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF5D4037).withValues(alpha: 0.75 + 0.2 * dirt),
              const Color(0xFF261A14).withValues(alpha: 0.9),
            ],
          ).createShader(Rect.fromLTRB(bounds.left, top, bounds.right, bounds.bottom)),
      );

      // …ve tüm akciğere is lekeleri yayılır; temizlendikçe şeffaflaşır.
      canvas.drawPath(
          lungs, Paint()..color = const Color(0xFF3E2723).withValues(alpha: 0.35 * dirt));
      final spot = Paint();
      final n = (_specks.length * dirt).round();
      for (var i = 0; i < n; i++) {
        final (sx, sy, sr) = _specks[i];
        spot.color = const Color(0xFF1B120E).withValues(alpha: 0.25 + 0.45 * dirt);
        canvas.drawCircle(
          Offset(bounds.left + sx * bounds.width, bounds.top + sy * bounds.height),
          1.2 + sr * 3.2,
          spot,
        );
      }
    }

    // Parlaklık (temizken daha belirgin)
    canvas.drawOval(
      Rect.fromLTWH(w * 0.14, h * 0.36, w * 0.10, h * 0.22),
      Paint()..color = Colors.white.withValues(alpha: 0.22 * (1 - dirt)),
    );
    canvas.drawOval(
      Rect.fromLTWH(w * 0.76, h * 0.36, w * 0.10, h * 0.22),
      Paint()..color = Colors.white.withValues(alpha: 0.22 * (1 - dirt)),
    );
    canvas.restore();

    // Kenar çizgisi
    canvas.drawPath(
      lungs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Color.lerp(const Color(0xFFFFCDD6), const Color(0xFF4E342E), dirt)!,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LungsPainter old) => old.dirt != dirt;
}
