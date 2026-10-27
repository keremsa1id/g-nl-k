import 'package:flutter/material.dart';

import 'theme.dart';

/// Sayfa üstündeki büyük başlık: küçük kırmızı üst etiket + kalın başlık + aksiyonlar.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.onTitleTap,
    this.actions = const [],
  });

  final String eyebrow;
  final String title;
  final VoidCallback? onTitleTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTitleTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppTheme.redBright,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      )),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            )),
                      ),
                      if (onTitleTap != null)
                        Icon(Icons.expand_more_rounded,
                            color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ],
              ),
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// Başlıktaki yuvarlak köşeli kare ikon butonu.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.surface2,
        fixedSize: const Size(46, 46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.border),
        ),
      ),
    );
  }
}

/// Bölüm başlığı (küçük, gri, büyük harf).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                )),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
