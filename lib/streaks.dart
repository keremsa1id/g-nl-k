import 'package:flutter/material.dart';

import 'models.dart';

/// Seri rozetleri: (gereken seri, emoji, ad).
const badgeTiers = <(int, String, String)>[
  (7, '🥉', 'Bronz'),
  (30, '🥈', 'Gümüş'),
  (100, '🥇', 'Altın'),
];

/// Seri uzadıkça alevin rengi değişir: turuncu → kırmızı → mor → mavi.
Color flameColor(int n) => n >= 100
    ? const Color(0xFF4DA3FF)
    : n >= 30
        ? const Color(0xFFE040FB)
        : n >= 7
            ? const Color(0xFFFF3B30)
            : const Color(0xFFFF8A1F);

/// Serinin ulaştığı en yüksek rozet; yoksa null.
String? badgeFor(int n) {
  String? b;
  for (final (min, emoji, _) in badgeTiers) {
    if (n >= min) b = emoji;
  }
  return b;
}

/// Seri tam olarak bir rozet eşiğine ulaştıysa o rozet.
(int, String, String)? tierReached(int n) =>
    badgeTiers.where((t) => t.$1 == n).firstOrNull;

String streakLabel(ScheduleItem i, int n) =>
    '$n ${i.repeat == Repeat.daily ? 'gün' : 'kez'} üst üste';
