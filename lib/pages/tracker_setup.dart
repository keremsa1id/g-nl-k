import 'package:flutter/material.dart';

import '../screen_time.dart';
import '../storage.dart';
import '../theme.dart';
import '../trackers.dart';

/// Yeni takip ekleme ya da var olanı düzenleme penceresi. Kaydedilen takibi döndürür.
Future<Tracker?> showTrackerSetup(BuildContext context, {Tracker? existing}) {
  return showModalBottomSheet<Tracker>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _TrackerSetupSheet(existing: existing),
  );
}

class _TrackerSetupSheet extends StatefulWidget {
  const _TrackerSetupSheet({this.existing});

  final Tracker? existing;

  @override
  State<_TrackerSetupSheet> createState() => _TrackerSetupSheetState();
}

class _TrackerSetupSheetState extends State<_TrackerSetupSheet> {
  final store = Store.instance;
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _log;
  late final TextEditingController _pack;
  late final TextEditingController _packSize;
  late final TextEditingController _packPrice;
  late String _emoji;
  late bool _purchases;
  late AutoMode _auto;
  late AppGroup _group;
  late List<String> _apps;
  final Map<String, String> _appLabels = {};
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _unit = TextEditingController(text: e?.unit ?? '');
    _log = TextEditingController(text: e?.logLabel ?? '');
    _pack = TextEditingController(text: e?.packName ?? '');
    _packSize = TextEditingController(text: '${e?.packSize ?? 1}');
    _packPrice = TextEditingController(text: _num(e?.packPrice ?? 0));
    _emoji = e?.emoji ?? '🎯';
    _purchases = e?.tracksPurchases ?? false;
    _auto = e?.autoMode ?? AutoMode.off;
    _group = e?.autoGroup ?? AppGroup.social;
    _apps = [...?e?.autoApps];
    if (_apps.isNotEmpty) _loadLabels();
  }

  Future<void> _loadLabels() async {
    try {
      final all = await ScreenTime.installedApps();
      if (!mounted) return;
      setState(() {
        for (final a in all) {
          _appLabels[a.package] = a.label;
        }
      });
    } catch (_) {}
  }

  /// Otomatik algılama için "Kullanım erişimi" izni gerekir; yoksa ayarlara yönlendir.
  Future<bool> _ensurePermission() async {
    if (await ScreenTime.hasPermission()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kullanım erişimi gerekli'),
        content: const Text(
            'Uygulamalara girdiğini otomatik algılamak için Ayarlar\'dan "Kullanım erişimi" '
            'iznini vermelisin. Veriler telefonundan çıkmaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ayarları aç')),
        ],
      ),
    );
    if (go == true) await ScreenTime.openSettings();
    return false;
  }

  Future<void> _setAuto(AutoMode mode) async {
    if (mode == _auto) return;
    // İzin yoksa ayarlara yönlendirilir; seçim yine kalır, izin gelince algılama başlar.
    if (mode != AutoMode.off) await _ensurePermission();
    if (!mounted) return;
    setState(() => _auto = mode);
    if (mode == AutoMode.apps && _apps.isEmpty) await _pickApps();
  }

  Future<void> _pickApps() async {
    if (!await ScreenTime.hasPermission()) {
      await _ensurePermission();
      return;
    }
    final all = await ScreenTime.installedApps();
    if (!mounted) return;
    for (final a in all) {
      _appLabels[a.package] = a.label;
    }
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _MultiAppPicker(apps: all, selected: _apps),
    );
    if (picked != null && mounted) {
      setState(() {
        _apps = picked;
        if (_apps.isEmpty && _auto == AutoMode.apps) _auto = AutoMode.off;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _unit, _log, _pack, _packSize, _packPrice]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _applyPreset(TrackerPreset p) {
    setState(() {
      _name.text = p.name;
      _unit.text = p.unit;
      _log.text = p.logLabel;
      _emoji = p.emoji;
      _purchases = p.packName.isNotEmpty;
      _pack.text = p.packName;
      _packSize.text = '${p.packSize}';
      _packPrice.text = _num(p.packPrice);
      final auto = ScreenTime.supported;
      _auto = auto ? p.autoMode : AutoMode.off;
      _group = p.autoGroup;
      _apps = auto ? [...p.autoApps] : [];
      if (_apps.isNotEmpty) _loadLabels();
      _error = null;
    });
    if (_auto != AutoMode.off) _ensurePermission();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Takip etmek istediğin şeyin adını yaz');
      return;
    }
    final clash = store.trackers.any(
        (t) => t.id != widget.existing?.id && t.name.toLowerCase() == name.toLowerCase());
    if (clash) {
      setState(() => _error = '"$name" zaten takip ediliyor');
      return;
    }
    final unit = _unit.text.trim().isEmpty ? 'kez' : _unit.text.trim();
    final log = _log.text.trim().isEmpty ? 'Yaptım' : _log.text.trim();
    final pack = _purchases ? (_pack.text.trim().isEmpty ? 'Alım' : _pack.text.trim()) : '';
    final size = int.tryParse(_packSize.text.trim()) ?? 1;
    final price = double.tryParse(_packPrice.text.replaceAll(',', '.').trim()) ?? 0;

    final t = widget.existing ??
        Tracker(id: 't${DateTime.now().millisecondsSinceEpoch}', name: name, emoji: _emoji,
            unit: unit, logLabel: log);
    t
      ..name = name
      ..emoji = _emoji
      ..unit = unit
      ..logLabel = log
      ..packName = pack
      ..packSize = size <= 0 ? 1 : size
      ..packPrice = price;

    // Otomatik algılama ayarı değiştiyse bu andan itibaren izle (geçmişe dönük kayıt yok).
    final mode = _auto == AutoMode.apps && _apps.isEmpty ? AutoMode.off : _auto;
    final apps = mode == AutoMode.apps ? _apps : <String>[];
    final changed = t.autoMode != mode ||
        t.autoApps.join(',') != apps.join(',') ||
        (mode == AutoMode.group && t.autoGroup != _group);
    t
      ..autoMode = mode
      ..autoGroup = _group
      ..autoApps = [...apps];
    if (mode == AutoMode.off) {
      t
        ..autoSync = null
        ..autoExit = null;
    } else if (changed) {
      t
        ..autoSync = DateTime.now()
        ..autoExit = null;
    }

    if (_isNew) {
      await store.addTracker(t);
    } else {
      await store.saveTrackers();
      store.trackersChanged.value++;
    }
    if (mounted) Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final taken = {for (final t in store.trackers) t.name.toLowerCase()};

    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isNew ? 'Neyi takip etmek istiyorsun?' : 'Takibi düzenle',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (_isNew) ...[
              const SizedBox(height: 4),
              Text('Bırakmak ya da azaltmak istediğin bir şey seç veya kendin yaz.',
                  style: TextStyle(color: muted)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.95,
                children: [
                  for (final p in trackerPresets)
                    Builder(builder: (_) {
                      final added = taken.contains(p.name.toLowerCase());
                      final selected = _name.text.trim() == p.name;
                      return GestureDetector(
                        onTap: added ? null : () => _applyPreset(p),
                        child: Opacity(
                          opacity: added ? 0.4 : 1,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.red.withValues(alpha: 0.2)
                                  : AppTheme.surface2,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: selected ? AppTheme.red : AppTheme.border,
                                  width: selected ? 1.6 : 1),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(p.emoji, style: const TextStyle(fontSize: 28)),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(added ? '${p.name} ✓' : p.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('ya da kendin oluştur',
                        style: TextStyle(fontSize: 12, color: muted)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(labelText: 'Adı (örn. Sigara, Alkol, Kola)'),
            ),
            const SizedBox(height: 12),
            Text('Simge', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in trackerEmojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _emoji == e ? AppTheme.red.withValues(alpha: 0.25) : AppTheme.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _emoji == e ? AppTheme.red : AppTheme.border),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                        labelText: 'Birim', hintText: 'sigara, kadeh…'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _log,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Buton yazısı', hintText: 'İçtim, Yedim…'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _purchases,
              onChanged: (v) => setState(() => _purchases = v),
              title: const Text('Harcamayı da takip et'),
              subtitle: Text('Paket, şişe gibi alımları ve harcadığın parayı kaydet',
                  style: TextStyle(color: muted, fontSize: 12)),
            ),
            if (_purchases) ...[
              TextField(
                controller: _pack,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Alım birimi', hintText: 'Paket, Şişe, Kutu…'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _packSize,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'İçindeki adet'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _packPrice,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Fiyat (₺)'),
                    ),
                  ),
                ],
              ),
            ],
            if (ScreenTime.supported) ...[
              const SizedBox(height: 14),
              Text('Otomatik algıla', style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(
                  'Uygulamaya her girdiğinde kayıt eklenir ve sayaç sıfırlanır; '
                  'uygulamadan çıkınca yeniden başlar.',
                  style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Kapalı'),
                    selected: _auto == AutoMode.off,
                    onSelected: (_) => _setAuto(AutoMode.off),
                  ),
                  ChoiceChip(
                    label: const Text('Uygulama grubu'),
                    selected: _auto == AutoMode.group,
                    onSelected: (_) => _setAuto(AutoMode.group),
                  ),
                  ChoiceChip(
                    label: const Text('Seçtiğim uygulamalar'),
                    selected: _auto == AutoMode.apps,
                    onSelected: (_) => _setAuto(AutoMode.apps),
                  ),
                ],
              ),
              if (_auto == AutoMode.group) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final g in AppGroup.values)
                      if (g != AppGroup.other)
                        ChoiceChip(
                          label: Text('${g.emoji} ${g.label}'),
                          selected: _group == g,
                          onSelected: (_) => setState(() => _group = g),
                        ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      _group == AppGroup.social
                          ? 'Instagram, X, TikTok, Facebook, WhatsApp, Snapchat, Reddit…'
                          : 'Telefonda bu gruba giren tüm uygulamalar',
                      style: TextStyle(color: muted, fontSize: 12)),
                ),
              ],
              if (_auto == AutoMode.apps)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_apps.isEmpty
                      ? 'Uygulama seç'
                      : _apps.map((p) => _appLabels[p] ?? p).join(', ')),
                  trailing: const Icon(Icons.edit_rounded, size: 18),
                  onTap: _pickApps,
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _save,
              icon: Text(_emoji, style: const TextStyle(fontSize: 18)),
              label: Text(_isNew ? 'Takibe başla' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Birden fazla uygulama seçilen arama listesi. Seçilen paket adlarını döner.
class _MultiAppPicker extends StatefulWidget {
  const _MultiAppPicker({required this.apps, required this.selected});

  final List<({String package, String label})> apps;
  final List<String> selected;

  @override
  State<_MultiAppPicker> createState() => _MultiAppPickerState();
}

class _MultiAppPickerState extends State<_MultiAppPicker> {
  late final Set<String> _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = [
      for (final a in widget.apps)
        if (q.isEmpty || a.label.toLowerCase().contains(q) || a.package.contains(q)) a,
    ]..sort((a, b) {
        final sa = _sel.contains(a.package) ? 0 : 1;
        final sb = _sel.contains(b.package) ? 0 : 1;
        return sa != sb ? sa - sb : a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  hintText: 'Uygulama ara (örn. instagram)',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Uygulama bulunamadı'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final a = list[i];
                        return CheckboxListTile(
                          value: _sel.contains(a.package),
                          title: Text(a.label),
                          subtitle: Text(a.package, style: const TextStyle(fontSize: 11)),
                          onChanged: (v) => setState(
                              () => v == true ? _sel.add(a.package) : _sel.remove(a.package)),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context, _sel.toList()),
                child: Text(_sel.isEmpty ? 'Tamam' : 'Tamam · ${_sel.length} uygulama'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
