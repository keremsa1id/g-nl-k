import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_links.dart';
import '../theme.dart';

/// Web sitesi açılınca gelen tanıtım sayfası: bilgisayarda QR kod (telefonla okutunca
/// Google Play), telefonda "Google Play'den indir" butonu. Altında tarayıcıda deneme.
class WebLandingPage extends StatelessWidget {
  const WebLandingPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  static const _features = [
    ('📅', 'Takvim ve alarm', 'Günlük program, hatırlatma, gerçek alarm'),
    ('🚬', 'Sigara takibi', 'Temiz kalma sayacı, kirlenip temizlenen akciğer'),
    ('❤️', 'Sağlık', 'Adım, uyku ve egzersiz (Health Connect)'),
    ('📱', 'Telefon kullanımı', 'Sosyal medya, oyun ve video süren'),
    ('🎙️', 'Sesle ekle', '"Yarın 9\'da spor" de, gerisini o halletsin'),
    ('🎮', 'XP ve mini oyunlar', 'Görevleri tamamla, seviye atla'),
  ];

  /// Web'i telefonda mı açtı (QR yerine buton gösterilir)?
  static bool get _onPhone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _openStore() async {
    if (!playStoreReady) return;
    await launchUrl(Uri.parse(playStoreUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.red,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('📅', style: TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 14),
            Text('Günlük',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 20),
        Text('Programın, alışkanlıkların ve sağlığın tek yerde.',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Günlük planını yap, sigarayı bırak, adımlarını ve ekran süreni takip et; '
            'yaptıkça XP kazan.',
            style: TextStyle(color: muted, fontSize: 15)),
        const SizedBox(height: 20),
        for (final (emoji, title, text) in _features)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
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
          ),
      ],
    );

    final download = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_onPhone) ...[
            Text('Telefonuna indir',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Kamerayla QR kodu okut', style: TextStyle(color: muted)),
            const SizedBox(height: 18),
            _qr(),
            const SizedBox(height: 18),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(240, 54)),
            onPressed: playStoreReady ? _openStore : null,
            icon: const Icon(Icons.shop_rounded),
            label: Text(playStoreReady ? 'Google Play\'den indir' : 'Yakında Google Play\'de'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onContinue,
            child: const Text('Tarayıcıda dene  →'),
          ),
          Text('Tarayıcıda bildirim, alarm ve sağlık verisi çalışmaz.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 860;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 20, vertical: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: intro),
                          const SizedBox(width: 48),
                          SizedBox(width: 360, child: download),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [intro, const SizedBox(height: 28), download],
                      ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Mağaza QR kodu. Uygulama henüz yayında değilse bulanık ve "Yakında" yazılı.
  Widget _qr() {
    final code = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: QrImageView(
        data: playStoreUrl,
        version: QrVersions.auto,
        size: 200,
        backgroundColor: Colors.white,
      ),
    );
    if (playStoreReady) return code;
    return Stack(
      alignment: Alignment.center,
      children: [
        ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: code),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('🚧 Yakında',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
