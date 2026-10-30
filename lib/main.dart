import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'game.dart';
import 'notifications.dart';
import 'pages/profile_page.dart';
import 'pages/schedule_page.dart';
import 'pages/tracker_page.dart';
import 'pages/tracker_setup.dart';
import 'storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.load();
  await Game.instance.load();
  await Notifier.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Günlük',
      navigatorKey: Notifier.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final store = Store.instance;
  int _index = 0; // 0 = Program, 1 = Profil, n+1 = n'inci takip
  late int _trackerCount = store.trackers.length;

  @override
  void initState() {
    super.initState();
    store.trackersChanged.addListener(_onTrackersChanged);
    Game.instance.changes.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Notifier.requestPermissions();
      await Notifier.rescheduleAll(Store.instance.items);
      await Notifier.openFromLaunch();
    });
  }

  @override
  void dispose() {
    store.trackersChanged.removeListener(_onTrackersChanged);
    Game.instance.changes.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Yeni takip eklenince onun sekmesine geç; kaldırılınca Program'a dön.
  void _onTrackersChanged() {
    final n = store.trackers.length;
    setState(() {
      if (n > _trackerCount) {
        _index = n + 1;
      } else if (n < _trackerCount || _index > n + 1) {
        _index = 0;
      }
      _trackerCount = n;
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // Uygulama kapalıyken bildirimden "Tamamlandı" basılmış olabilir.
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;
    await Store.instance.reloadDone();
    Notifier.changes.value++;
    await Notifier.refreshExtras();
  }

  @override
  Widget build(BuildContext context) {
    final trackers = store.trackers;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const SchedulePage(),
          // const değil: sekmeye her geçişte güncel XP / görevlerle yeniden çizilir.
          // ignore: prefer_const_constructors
          ProfilePage(),
          for (final t in trackers) TrackerPage(key: ValueKey(t.id), trackerId: t.id),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [
                BoxShadow(color: Colors.black, blurRadius: 24, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                _NavItem(
                  leading: Icon(Icons.calendar_month_rounded,
                      color: _index == 0 ? Colors.white : AppTheme.scheme.onSurfaceVariant,
                      size: 22),
                  label: 'Program',
                  // Seçiliyse ya da hiç takip yoksa yazı görünür; yoksa sadece simge.
                  showLabel: _index == 0 || trackers.isEmpty,
                  selected: _index == 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _NavItem(
                  leading: Badge(
                    isLabelVisible: Game.instance.unclaimedCount > 0,
                    label: Text('${Game.instance.unclaimedCount}'),
                    child: Icon(Icons.emoji_events_rounded,
                        color: _index == 1 ? Colors.white : AppTheme.scheme.onSurfaceVariant,
                        size: 22),
                  ),
                  label: 'Profil',
                  showLabel: _index == 1 || trackers.isEmpty,
                  selected: _index == 1,
                  onTap: () => setState(() => _index = 1),
                ),
                for (final (i, t) in trackers.indexed)
                  _NavItem(
                    leading: Text(t.emoji, style: const TextStyle(fontSize: 20)),
                    label: t.name,
                    showLabel: _index == i + 2 || trackers.isEmpty,
                    selected: _index == i + 2,
                    onTap: () => setState(() => _index = i + 2),
                  ),
                const SizedBox(width: 4),
                // Yeni takip ekle
                Tooltip(
                  message: 'Takip ekle',
                  child: GestureDetector(
                    onTap: () => showTrackerSetup(context),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.surface3,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yüzen alt menüdeki hap şeklindeki sekme.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.leading,
    required this.label,
    required this.showLabel,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final bool showLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTheme.scheme.onSurfaceVariant;
    return Expanded(
      flex: showLabel ? 3 : 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.red : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.45), blurRadius: 16)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              if (showLabel) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      )),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
