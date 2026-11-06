import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auto_track.dart';
import 'game.dart';
import 'home_widgets.dart';
import 'notifications.dart';
import 'pages/launcher_page.dart';
import 'pages/profile_page.dart';
import 'pages/schedule_page.dart';
import 'pages/tracker_page.dart';
import 'pages/tracker_setup.dart';
import 'pages/web_landing_page.dart';
import 'pages/wellbeing_page.dart';
import 'storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.load();
  await Game.instance.load();
  await Notifier.init();
  await HomeWidgets.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ritmo',
      navigatorKey: Notifier.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Root(),
    );
  }
}

/// Profil doldurulmadıysa önce zorunlu profil ekranı, sonra ana ekran.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _ready = Game.instance.profile.isComplete;
  bool _webIntro = kIsWeb; // web sitesi: önce tanıtım ve indirme sayfası

  @override
  Widget build(BuildContext context) {
    if (_webIntro) return WebLandingPage(onContinue: () => setState(() => _webIntro = false));
    if (_ready) return const HomeShell();
    return ProfileSetupPage(onDone: () => setState(() => _ready = true));
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final store = Store.instance;
  int _index = 0; // 0 = Program, 1 = Sağlık, n + 1 = n'inci takip
  bool _wellOpened = false; // Sağlık sekmesi ilk açılınca kurulur
  bool _launcher = true; // açılışta büyük kutucuklu giriş ekranı
  DateTime? _pausedAt;

  /// Giriş ekranında bir kutucuk seçildi.
  void _openFromLauncher(int index, int? tab) {
    setState(() {
      if (index == 1) {
        _wellOpened = true;
        if (tab != null) WellbeingPage.tab.value = tab;
      }
      _index = index;
      _launcher = false;
    });
  }
  late int _trackerCount = store.trackers.length;

  @override
  void initState() {
    super.initState();
    store.trackersChanged.addListener(_onTrackersChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ana ekran widget'ından açıldıysa (ör. Hızlı ekle) önce onu yap.
      await HomeWidgets.listen(_onWidgetUri);
      unawaited(HomeWidgets.update());
      await Notifier.requestPermissions();
      await Notifier.rescheduleAll(Store.instance.items);
      await Notifier.openFromLaunch();
      await AutoTrack.sync();
      await Game.instance.refreshScreenTime();
      await Game.instance.refreshHealth();
    });
  }

  @override
  void dispose() {
    store.trackersChanged.removeListener(_onTrackersChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime? _lastWidgetUri;

  /// gunluk://voice -> Program sekmesinde sesli ekleme, gunluk://open -> Program.
  void _onWidgetUri(Uri uri) {
    // Soğuk açılışta aynı dokunuş iki yoldan gelebilir.
    final now = DateTime.now();
    if (_lastWidgetUri != null && now.difference(_lastWidgetUri!).inSeconds < 2) return;
    _lastWidgetUri = now;
    if (!mounted) return;
    setState(() {
      _index = 0;
      _launcher = false;
    });
    if (uri.host == 'voice') SchedulePage.quickAddRequest.value++;
  }

  /// Yeni takip eklenince onun sekmesine geç; kaldırılınca Program'a dön.
  void _onTrackersChanged() {
    final n = store.trackers.length;
    setState(() {
      if (n > _trackerCount) {
        _index = n + 1;
        _launcher = false;
      } else if (n < _trackerCount || _index > n + 1) {
        _index = 0;
      }
      _trackerCount = n;
    });
  }

  // Uygulama kapalıyken bildirimden "Tamamlandı" basılmış olabilir.
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    // Uygulamadan çıkarken ana ekran widget'ını güncelle.
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      await HomeWidgets.update();
    }
    if (state != AppLifecycleState.resumed) return;
    // Uzun süre (30 dk+) sonra dönünce giriş ekranı yeniden gelsin.
    final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
    _pausedAt = null;
    if (away >= const Duration(minutes: 30) && mounted) setState(() => _launcher = true);
    // Widget'tan sesle eklenen etkinlik, ✅ ya da bildirimden "Tamamlandı" olmuş olabilir.
    await Store.instance.load(fresh: true);
    if (mounted) setState(() {});
    Notifier.changes.value++;
    await Notifier.refreshExtras();
    await AutoTrack.sync();
    if (mounted) setState(() {});
    await Game.instance.refreshScreenTime();
    await Game.instance.refreshHealth();
    // Widget'tan ✅ basılmış olabilir.
    await HomeWidgets.update();
  }

  @override
  Widget build(BuildContext context) {
    final trackers = store.trackers;
    final shell = Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const SchedulePage(),
          if (_wellOpened) const WellbeingPage() else const SizedBox.shrink(),
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
                  // Seçiliyse ya da en fazla bir takip varsa yazı görünür; yoksa sadece simge.
                  showLabel: _index == 0 || trackers.length < 2,
                  selected: _index == 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _NavItem(
                  leading: Icon(Icons.favorite_rounded,
                      color: _index == 1 ? Colors.white : AppTheme.scheme.onSurfaceVariant,
                      size: 22),
                  label: 'Sağlık',
                  showLabel: _index == 1,
                  selected: _index == 1,
                  onTap: () => setState(() {
                    _index = 1;
                    _wellOpened = true;
                  }),
                ),
                for (final (i, t) in trackers.indexed)
                  _NavItem(
                    leading: Text(t.emoji, style: const TextStyle(fontSize: 20)),
                    label: t.name,
                    showLabel: _index == i + 2 || trackers.length < 2,
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
    // Giriş ekranı, alttaki sayfalar kurulu kalsın diye üstte durur
    // (ör. widget'tan sesli ekleme gelince Program sayfası hazır olmalı).
    return PopScope(
      // Bir bölümdeyken geri tuşu giriş ekranına döner; giriş ekranında uygulamadan çıkar.
      canPop: _launcher,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _launcher = true);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          shell,
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _launcher
                ? LauncherPage(key: const ValueKey('launcher'), onOpen: _openFromLauncher)
                : const SizedBox.shrink(),
          ),
        ],
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
