import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

/// Ekran süresi grupları.
enum AppGroup { social, game, video, music, other }

extension AppGroupX on AppGroup {
  String get label => switch (this) {
        AppGroup.social => 'Sosyal medya',
        AppGroup.game => 'Oyun',
        AppGroup.video => 'Video',
        AppGroup.music => 'Müzik',
        AppGroup.other => 'Diğer',
      };

  String get emoji => switch (this) {
        AppGroup.social => '💬',
        AppGroup.game => '🎮',
        AppGroup.video => '🎬',
        AppGroup.music => '🎵',
        AppGroup.other => '📱',
      };

  Color get color => switch (this) {
        AppGroup.social => const Color(0xFFFF4D6D),
        AppGroup.game => const Color(0xFF9B5DE5),
        AppGroup.video => const Color(0xFFFFB020),
        AppGroup.music => const Color(0xFF2EC4B6),
        AppGroup.other => const Color(0xFF757575),
      };
}

/// Android'in kategorisi boş bırakılan bilinen uygulamalar.
const _knownApps = <String, AppGroup>{
  'com.instagram.android': AppGroup.social,
  'com.instagram.barcelona': AppGroup.social, // Threads
  'com.facebook.katana': AppGroup.social,
  'com.facebook.lite': AppGroup.social,
  'com.facebook.orca': AppGroup.social, // Messenger
  'com.whatsapp': AppGroup.social,
  'com.whatsapp.w4b': AppGroup.social,
  'com.twitter.android': AppGroup.social,
  'com.zhiliaoapp.musically': AppGroup.social, // TikTok
  'com.ss.android.ugc.trill': AppGroup.social,
  'com.snapchat.android': AppGroup.social,
  'org.telegram.messenger': AppGroup.social,
  'com.reddit.frontpage': AppGroup.social,
  'com.linkedin.android': AppGroup.social,
  'com.pinterest': AppGroup.social,
  'com.discord': AppGroup.social,
  'com.tumblr': AppGroup.social,
  'com.bereal.ft': AppGroup.social,
  'com.google.android.youtube': AppGroup.video,
  'com.netflix.mediaclient': AppGroup.video,
  'tv.twitch.android.app': AppGroup.video,
  'com.amazon.avod.thirdpartyclient': AppGroup.video,
  'com.disney.disneyplus': AppGroup.video,
  'com.spotify.music': AppGroup.music,
  'com.google.android.apps.youtube.music': AppGroup.music,
  'com.apple.android.music': AppGroup.music,
};

/// Android ApplicationInfo.category değerleri.
AppGroup _groupFor(String package, int category) {
  final known = _knownApps[package];
  if (known != null) return known;
  return switch (category) {
    0 => AppGroup.game,
    1 => AppGroup.music,
    2 => AppGroup.video,
    4 => AppGroup.social,
    _ => AppGroup.other,
  };
}

class AppUsage {
  const AppUsage(this.package, this.label, this.group, this.duration, this.launches);

  final String package;
  final String label;
  final AppGroup group;
  final Duration duration;
  final int launches;
}

/// Telefonun uygulama kullanım istatistikleri (yalnızca Android).
class ScreenTime {
  static const _channel = MethodChannel('gunluk/usage');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> hasPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }

  /// [from, to) arasındaki kullanım, en çok kullanılandan aza.
  static Future<List<AppUsage>> query(DateTime from, DateTime to) async {
    if (!supported) return [];
    final raw = await _channel.invokeMethod<List<Object?>>('query', {
      'start': from.millisecondsSinceEpoch,
      'end': to.millisecondsSinceEpoch,
    });
    final list = <AppUsage>[
      for (final e in raw ?? const <Object?>[])
        if (e is Map)
          AppUsage(
            e['package'] as String,
            e['label'] as String,
            _groupFor(e['package'] as String, (e['category'] as num).toInt()),
            Duration(milliseconds: (e['ms'] as num).toInt()),
            (e['launches'] as num).toInt(),
          ),
    ]..sort((a, b) => b.duration.compareTo(a.duration));
    return list;
  }
}

/// "2 sa 15 dk" / "45 dk" / "<1 dk".
String fmtUsage(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return '<1 dk';
  if (m < 60) return '$m dk';
  return m % 60 == 0 ? '${m ~/ 60} sa' : '${m ~/ 60} sa ${m % 60} dk';
}
