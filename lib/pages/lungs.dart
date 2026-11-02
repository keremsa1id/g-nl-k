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
/// 1 sigara ≈ %6, art arda 5 ≈ %26; günde bir paket birkaç günde ~%75'e oturur.
const _perSmoke = 0.06;
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
              child: Text('🫁 $label · ~%${(d * 100).round()} kirli',
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
            const SizedBox(height: 6),
            // Tıbbi veri olmadığı açıkça görünsün; dokununca açıklama açılır.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Bu gerçek bir ölçüm değil'),
                  content: const Text(
                    'Akciğer çizimi ve kirlilik yüzdesi yalnızca motivasyon amaçlı bir '
                    'canlandırmadır. Vücudundan hiçbir veri ölçülmez; değer, girdiğin sigara '
                    'kayıtlarından basit bir formülle hesaplanır.\n\n'
                    'Gerçek akciğer iyileşmesi aylar ile yıllar sürer ve kişiden kişiye '
                    'değişir. Sağlığınla ilgili bilgi için bir doktora danış.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Anladım'),
                    ),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: muted),
                    const SizedBox(width: 4),
                    Text('Temsili canlandırma · tıbbi ölçüm değildir',
                        style: TextStyle(
                            fontSize: 11,
                            color: muted,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// El çizimi tarzı akciğer: titrek mürekkep kontur, soluk borusu halkaları,
/// bronş ağacı, lob çizgileri ve tarama gölge. Kirlendikçe katran dolar.
class _LungsPainter extends CustomPainter {
  _LungsPainter(this.dirt, this.breath) : super(repaint: breath);

  final double dirt; // 0..1
  final Animation<double> breath; // 0..1

  // Kir lekelerinin yerleri sabit kalsın diye bir kez üretilir (0..1 koordinatları).
  static final List<(double, double, double)> _specks = () {
    final r = Random(42);
    return [for (var i = 0; i < 90; i++) (r.nextDouble(), r.nextDouble(), r.nextDouble())];
  }();

  // Görüntünün solundaki akciğer (anatomik sağ: 3 lob).
  Path _leftLung(double w, double h) => Path()
    ..moveTo(w * 0.43, h * 0.22)
    ..cubicTo(w * 0.33, h * 0.14, w * 0.20, h * 0.24, w * 0.13, h * 0.42)
    ..cubicTo(w * 0.06, h * 0.60, w * 0.04, h * 0.82, w * 0.10, h * 0.93)
    ..cubicTo(w * 0.17, h * 0.99, w * 0.30, h * 0.93, w * 0.40, h * 0.90)
    ..cubicTo(w * 0.46, h * 0.88, w * 0.47, h * 0.82, w * 0.46, h * 0.74)
    ..cubicTo(w * 0.45, h * 0.60, w * 0.47, h * 0.40, w * 0.43, h * 0.22)
    ..close();

  /// Yolu hafifçe titreterek elle çizilmiş gibi gösterir (her karede aynı sonuç).
  static Path _sketch(Path src, double amp, double seed) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var first = true;
      for (var d = 0.0; d <= m.length; d += 3) {
        final t = m.getTangentForOffset(d)!;
        final n = Offset(-t.vector.dy, t.vector.dx);
        final j = amp * (0.6 * sin(d * 0.11 + seed) + 0.4 * sin(d * 0.037 + seed * 2.3));
        final p = t.position + n * j;
        if (first) {
          out.moveTo(p.dx, p.dy);
          first = false;
        } else {
          out.lineTo(p.dx, p.dy);
        }
      }
      if (m.isClosed) out.close();
    }
    return out;
  }

  /// Bronş ağacı: (başlangıç, bitiş, derinlik) parçaları.
  static void _branch(
      List<(Offset, Offset, int)> out, Offset from, double angle, double len, int depth) {
    final to = from + Offset(cos(angle), sin(angle)) * len;
    out.add((from, to, depth));
    if (depth == 0) return;
    _branch(out, to, angle - 0.42, len * 0.7, depth - 1);
    _branch(out, to, angle + 0.36, len * 0.66, depth - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final b = Curves.easeInOut.transform(breath.value);

    final ink = Color.lerp(const Color(0xFF6B2737), const Color(0xFF2B1B17), dirt)!;
    final tissueTop = Color.lerp(const Color(0xFFFFBFCB), const Color(0xFFC9A49B), dirt * 0.6)!;
    final tissueBottom = Color.lerp(const Color(0xFFF4889E), const Color(0xFF9C6B60), dirt * 0.6)!;
    final airFill = Color.lerp(const Color(0xFFF7B3C2), const Color(0xFF8D6E63), dirt * 0.7)!;
    final treeColor = Color.lerp(const Color(0xFFD45C78), const Color(0xFF4E342E), dirt)!;

    // Nefes: ortadan biraz genişleyip daralır.
    canvas.save();
    canvas.translate(w / 2, h * 0.55);
    canvas.scale(0.95 + 0.05 * b, 0.97 + 0.03 * b);
    canvas.translate(-w / 2, -h * 0.55);

    final left = _leftLung(w, h);
    final mirror = Float64List.fromList(
        [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, w, 0, 0, 1]);
    final right = left.transform(mirror);
    final lungs = Path()
      ..addPath(left, Offset.zero)
      ..addPath(right, Offset.zero);
    final bounds = lungs.getBounds();

    // Soluk borusu ve ana bronşlar: konturlu tüp (akciğerlerin arkasında kalır).
    final tube = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.5, h * 0.24)
      ..moveTo(w * 0.5, h * 0.22)
      ..quadraticBezierTo(w * 0.46, h * 0.30, w * 0.36, h * 0.36)
      ..moveTo(w * 0.5, h * 0.22)
      ..quadraticBezierTo(w * 0.54, h * 0.30, w * 0.64, h * 0.36);
    final tubePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        tube,
        tubePaint
          ..color = ink
          ..strokeWidth = w * 0.09 + 5);
    canvas.drawPath(
        tube,
        tubePaint
          ..color = airFill
          ..strokeWidth = w * 0.09);
    // Kıkırdak halkaları
    final rings = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    for (var y = h * 0.03; y < h * 0.21; y += h * 0.032) {
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.465, y)
          ..quadraticBezierTo(w * 0.5, y + h * 0.014, w * 0.535, y),
        rings,
      );
    }

    // Doku: yumuşak pembe dolgu
    canvas.drawPath(
      lungs,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tissueTop, tissueBottom],
        ).createShader(bounds),
    );

    canvas.save();
    canvas.clipPath(lungs);

    // Tarama gölge: her akciğerin dış-alt kenarında hilal şeklinde.
    final shade = Path.combine(
      PathOperation.difference,
      lungs,
      Path()
        ..addPath(left, Offset(w * 0.05, -h * 0.06))
        ..addPath(right, Offset(-w * 0.05, -h * 0.06)),
    );
    canvas.save();
    canvas.clipPath(shade);
    final hatch = Paint()
      ..color = ink.withValues(alpha: 0.35)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var x = -h; x < w; x += 5) {
      canvas.drawLine(Offset(x, h), Offset(x + h, 0), hatch);
    }
    canvas.restore();

    // Bronş ağacı (sol akciğerde üretilir, sağa aynalanır)
    final segs = <(Offset, Offset, int)>[];
    _branch(segs, Offset(w * 0.36, h * 0.36), pi * 0.64, w * 0.15, 3);
    final tree = Paint()
      ..color = treeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (a, z, depth) in segs) {
      tree.strokeWidth = 1.0 + depth * 1.1;
      canvas.drawLine(a, z, tree);
      canvas.drawLine(Offset(w - a.dx, a.dy), Offset(w - z.dx, z.dy), tree);
    }

    // Lob çizgileri (solda iki, sağda bir yarık)
    final fissure = Paint()
      ..color = ink.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8;
    canvas.drawPath(
      _sketch(
        Path()
          ..moveTo(w * 0.16, h * 0.36)
          ..quadraticBezierTo(w * 0.30, h * 0.62, w * 0.40, h * 0.90)
          ..moveTo(w * 0.07, h * 0.60)
          ..quadraticBezierTo(w * 0.17, h * 0.55, w * 0.26, h * 0.57),
        0.8,
        3,
      ),
      fissure,
    );
    canvas.drawPath(
      _sketch(
        Path()
          ..moveTo(w * 0.84, h * 0.38)
          ..quadraticBezierTo(w * 0.72, h * 0.60, w * 0.62, h * 0.90),
        0.8,
        5,
      ),
      fissure,
    );

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
              const Color(0xFF5D4037).withValues(alpha: 0.7 + 0.2 * dirt),
              const Color(0xFF261A14).withValues(alpha: 0.9),
            ],
          ).createShader(Rect.fromLTRB(bounds.left, top, bounds.right, bounds.bottom)),
      );
      // Katranın üst sınırı da mürekkeple çizilsin
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF1B120E).withValues(alpha: 0.6),
      );

      // …ve tüm akciğere is lekeleri yayılır; temizlendikçe şeffaflaşır.
      canvas.drawPath(
          lungs, Paint()..color = const Color(0xFF3E2723).withValues(alpha: 0.3 * dirt));
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

    // Çizgi film parlaması: kısa beyaz kavis + nokta (temizken belirgin)
    final shine = Paint()
      ..color = Colors.white.withValues(alpha: 0.6 * (1 - dirt))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.6 * (1 - dirt));
    for (final flip in [false, true]) {
      double x(double v) => flip ? w - v : v;
      canvas.drawPath(
        Path()
          ..moveTo(x(w * 0.24), h * 0.30)
          ..quadraticBezierTo(x(w * 0.15), h * 0.40, x(w * 0.13), h * 0.54),
        shine,
      );
      canvas.drawCircle(Offset(x(w * 0.125), h * 0.61), 2, dot);
    }
    canvas.restore();

    // Mürekkep kontur: kalın ana çizgi + üstüne ince ikinci "kalem" geçişi.
    canvas.drawPath(
      _sketch(lungs, 0.9, 1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    );
    canvas.drawPath(
      _sketch(lungs, 1.4, 7).shift(const Offset(0.8, -0.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink.withValues(alpha: 0.45),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LungsPainter old) => old.dirt != dirt;
}
