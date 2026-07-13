import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'singbox_engine.dart';
import 'subscription.dart';

void main() => runApp(const NstTunnelApp());

// Happ-inspired deep indigo palette
const kBrand = Color(0xFF6C7BFF);
const kBrandDim = Color(0xFF5B63F5);
const kBg = Color(0xFF0E1330);
const kPanel = Color(0xFF141A3C);
const kSurface = Color(0xFF1B1740);
const kSurface2 = Color(0xFF242A52);
const kGood = Color(0xFF83D6B5);
const kWarn = Color(0xFFFFB02E);
const kBad = Color(0xFFFF8A80);
const kAccentBlue = Color(0xFF6C7BFF);

class ProxyConfig {
  final String protocol, name, address, raw;
  final int port;
  String group;
  bool pinned;
  int? ping;
  ProxyConfig({required this.protocol, required this.name, required this.address, required this.port, required this.group, required this.raw, this.pinned = false, this.ping});
  Map<String, dynamic> toJson() => {'raw': raw, 'group': group, 'pinned': pinned};
  String get flag => _flagFor(name);
  String get transport => _transportOf(raw);
}

class Subscription {
  String name;
  final String url;
  Subscription({required this.name, required this.url});
  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  static Subscription fromJson(Map j) => Subscription(name: j['name'], url: j['url']);
}

String _transportOf(String raw) {
  try {
    if (raw.startsWith('vmess://')) {
      final j = jsonDecode(utf8.decode(base64.decode(base64.normalize(raw.substring(8)))));
      final net = (j['net'] ?? 'tcp').toString().toUpperCase();
      final tls = (j['tls'] ?? '').toString();
      return tls.isEmpty ? net : net + ' / ' + tls.toUpperCase();
    }
    final u = Uri.parse(raw);
    final q = u.queryParameters;
    final net = (q['type'] ?? 'tcp').toUpperCase();
    final sec = (q['security'] ?? '').toUpperCase();
    return sec.isEmpty ? net : net + ' / ' + sec;
  } catch (_) { return ''; }
}

String _flagFor(String s) {
  final t = s.toLowerCase();
  final map = <String, List<String>>{
    '🇳🇱': ['nether','amsterdam','nl','🇳🇱'], '🇩🇪': ['german','frankfurt','🇩🇪'],
    '🇺🇸': ['usa','united states','🇺🇸'], '🇬🇧': ['london','uk ','🇬🇧'],
    '🇫🇷': ['france','paris','🇫🇷'], '🇯🇵': ['japan','tokyo','🇯🇵'],
    '🇸🇬': ['singapore','🇸🇬'], '🇷🇺': ['russia','moscow','🇷🇺'],
    '🇫🇮': ['finland','🇫🇮'], '🇸🇪': ['sweden','🇸🇪'], '🇹🇷': ['turkey','istanbul','🇹🇷'],
    '🇦🇪': ['emirat','dubai','🇦🇪'], '🇦🇺': ['austral','sydney','🇦🇺'], '🇧🇪': ['belgium','🇧🇪'],
    '🇨🇭': ['switz','zurich','🇨🇭'], '🇧🇿': ['belize','🇧🇿'], '🇨🇦': ['canada','🇨🇦'],
    '🇵🇱': ['poland','warsaw','🇵🇱'], '🇮🇳': ['india','🇮🇳'], '🇭🇰': ['hong kong','🇭🇰'],
    '🇰🇿': ['kazakh','🇰🇿'], '🇺🇦': ['ukrain','🇺🇦'], '🇪🇸': ['spain','madrid','🇪🇸'],
    '🇮🇹': ['italy','milan','🇮🇹'], '🇧🇷': ['brazil','🇧🇷'], '🇰🇷': ['korea','seoul','🇰🇷'],
  };
  for (final e in map.entries) { for (final k in e.value) { if (t.contains(k)) return e.key; } }
  return '🌐';
}

class ConfigParser {
  static List<ProxyConfig> parseMany(String text, String group) {
    final out = <ProxyConfig>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final c = parseOne(l, group);
      if (c != null) out.add(c);
    }
    return out;
  }
  static String normalizeBody(String body) {
    final t = body.trim();
    if (t.contains('://')) return t;
    try { final f = base64.normalize(t.replaceAll(RegExp(r'\s'), '')); final d = utf8.decode(base64.decode(f), allowMalformed: true); if (d.contains('://')) return d; } catch (_) {}
    return t;
  }
  static ProxyConfig? parseOne(String link, String group) {
    try {
      if (link.startsWith('vmess://')) return _vmess(link, group);
      if (link.startsWith('vless://')) return _generic(link, 'vless', group);
      if (link.startsWith('trojan://')) return _generic(link, 'trojan', group);
      if (link.startsWith('ss://')) return _ss(link, group);
      if (link.startsWith('hysteria2://')) return _generic(link, 'hysteria2', group);
      if (link.startsWith('hy2://')) return _generic(link, 'hysteria2', group);
      if (link.startsWith('hysteria://')) return _generic(link, 'hysteria', group);
      if (link.startsWith('tuic://')) return _generic(link, 'tuic', group);
    } catch (_) {}
    return null;
  }
  static String _tag(Uri u) { if (u.fragment.isEmpty) return ''; try { return Uri.decodeComponent(u.fragment); } catch (_) { return u.fragment; } }
  static ProxyConfig _generic(String link, String proto, String g) {
    final u = Uri.parse(link); final name = _tag(u);
    return ProxyConfig(protocol: proto, name: name.isEmpty ? proto + ' ' + u.host : name, address: u.host, port: u.port == 0 ? 443 : u.port, group: g, raw: link);
  }
  static ProxyConfig _vmess(String link, String g) {
    final j = jsonDecode(utf8.decode(base64.decode(base64.normalize(link.substring(8)))));
    final name = (j['ps'] ?? '').toString(); final host = (j['add'] ?? '').toString();
    final port = int.tryParse((j['port'] ?? '443').toString()) ?? 443;
    return ProxyConfig(protocol: 'vmess', name: name.isEmpty ? 'vmess ' + host : name, address: host, port: port, group: g, raw: link);
  }
  static ProxyConfig _ss(String link, String g) {
    final u = Uri.parse(link); final name = _tag(u); String host = u.host; int port = u.port;
    if (host.isEmpty) {
      final body = link.substring(5).split('#').first;
      final dec = utf8.decode(base64.decode(base64.normalize(body)), allowMalformed: true);
      final at = dec.lastIndexOf('@');
      if (at != -1) { final hp = dec.substring(at+1).split(':'); host = hp.first; port = int.tryParse(hp.length>1?hp[1]:'443') ?? 443; }
    }
    if (port == 0) port = 443;
    return ProxyConfig(protocol: 'ss', name: name.isEmpty ? 'ss ' + host : name, address: host, port: port, group: g, raw: link);
  }
}

class Pinger {
  static Future<int> ping(ProxyConfig c) async {
    final sw = Stopwatch()..start();
    try { final s = await Socket.connect(c.address, c.port, timeout: const Duration(seconds: 4)); sw.stop(); s.destroy(); return sw.elapsedMilliseconds; } catch (_) {}
    try { sw..reset()..start(); final cl = http.Client(); final sch = c.port == 80 ? 'http' : 'https'; await cl.head(Uri.parse(sch + '://' + c.address + ':' + c.port.toString())).timeout(const Duration(seconds: 4)); sw.stop(); cl.close(); return sw.elapsedMilliseconds; } catch (_) {}
    return -1;
  }
}

class Store {
  static const _cfgKey = 'nst_cfg_v3';
  static const _subKey = 'nst_sub_v3';
  static Future<(List<ProxyConfig>, List<Subscription>)> load() async {
    final p = await SharedPreferences.getInstance();
    final cfgs = <ProxyConfig>[];
    for (final s in (p.getStringList(_cfgKey) ?? const <String>[])) {
      try { final j = jsonDecode(s); final c = ConfigParser.parseOne(j['raw'], j['group'] ?? 'Imported'); if (c != null) { c.pinned = j['pinned'] == true; cfgs.add(c); } } catch (_) {}
    }
    final subs = <Subscription>[];
    for (final s in (p.getStringList(_subKey) ?? const <String>[])) {
      try { subs.add(Subscription.fromJson(jsonDecode(s))); } catch (_) {}
    }
    return (cfgs, subs);
  }
  static Future<void> save(List<ProxyConfig> cfgs, List<Subscription> subs) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_cfgKey, cfgs.map((c) => jsonEncode(c.toJson())).toList());
    await p.setStringList(_subKey, subs.map((s) => jsonEncode(s.toJson())).toList());
  }
}

class NstTunnelApp extends StatelessWidget {
  const NstTunnelApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kBrand, brightness: Brightness.dark).copyWith(primary: kBrand, surface: kSurface);
    return MaterialApp(title: 'NST Tunnel', debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: kBg, fontFamily: 'Segoe UI'),
      home: const HomeShell());
  }
}

enum ConnState { off, connecting, on }
enum RouteMode { proxy, tun }

Color pingColor(int? ms) { if (ms == null) return Colors.white38; if (ms < 0) return kBad; if (ms < 150) return kGood; if (ms < 350) return kWarn; return kBad; }
String pingLabel(int? ms) => ms == null ? '—' : ms < 0 ? 'timeout' : ms.toString() + ' ms';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  List<ProxyConfig> _configs = [];
  List<Subscription> _subs = [];
  ProxyConfig? _selected;
  bool _loading = true;
  ConnState _conn = ConnState.off;
  RouteMode _mode = RouteMode.proxy;
  int _rail = 0;
  String _query = '';

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final res = await Store.load();
    setState(() { _configs = res.$1; _subs = res.$2; _selected = _configs.isNotEmpty ? _configs.first : null; _loading = false; });
  }
  Future<void> _persist() async => Store.save(_configs, _subs);

  Future<void> _addConfigs(List<ProxyConfig> added, {Subscription? sub}) async {
    if (added.isEmpty) return;
    if (sub != null && !_subs.any((s) => s.url == sub.url)) _subs.add(sub);
    final existing = _configs.map((e) => e.raw).toSet();
    final fresh = added.where((c) => !existing.contains(c.raw)).toList();
    setState(() { _configs = [..._configs, ...fresh]; _selected ??= _configs.isNotEmpty ? _configs.first : null; });
    await _persist();
    _toast('Импортировано: ' + fresh.length.toString());
  }

  void _toast(String msg) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: kBrandDim)); }

  Future<void> _updateGroup(String group) async {
    Subscription? sub;
    for (final s in _subs) { if (s.name == group) { sub = s; break; } }
    if (sub == null) { _toast('Нет URL подписки для "' + group + '"'); return; }
    try {
      final body = await SubscriptionFetcher.fetch(sub.url);
      final parsed = ConfigParser.parseMany(body, group);
      if (parsed.isEmpty) { _toast('Обновление вернуло 0 конфигов'); return; }
      setState(() {
        _configs.removeWhere((c) => c.group == group);
        _configs.addAll(parsed);
        if (_selected != null && !_configs.contains(_selected)) _selected = _configs.isNotEmpty ? _configs.first : null;
      });
      await _persist();
      _toast('Обновлено "' + group + '": ' + parsed.length.toString());
    } catch (e) { _toast('Ошибка обновления: ' + e.toString()); }
  }

  Future<void> _renameGroup(String oldName, String newName) async {
    if (newName.trim().isEmpty || newName == oldName) return;
    setState(() { for (final c in _configs) { if (c.group == oldName) c.group = newName; } for (final s in _subs) { if (s.name == oldName) s.name = newName; } });
    await _persist();
  }

  void _removeGroup(String g) async {
    setState(() { _configs.removeWhere((c) => c.group == g); _subs.removeWhere((s) => s.name == g); if (_selected != null && !_configs.contains(_selected)) _selected = _configs.isNotEmpty ? _configs.first : null; });
    await _persist();
  }
  void _remove(ProxyConfig c) async { setState(() { _configs.remove(c); if (_selected == c) _selected = _configs.isNotEmpty ? _configs.first : null; }); await _persist(); }
  void _togglePin(ProxyConfig c) async { setState(() => c.pinned = !c.pinned); await _persist(); }
  void _select(ProxyConfig c) => setState(() => _selected = c);

  Future<void> _pingAll() async { await Future.wait(_configs.map((c) async { c.ping = await Pinger.ping(c); if (mounted) setState(() {}); })); }
  Future<void> _pingGroup(String g) async { await Future.wait(_configs.where((c) => c.group == g).map((c) async { c.ping = await Pinger.ping(c); if (mounted) setState(() {}); })); }
  Future<void> _pingOne(ProxyConfig c) async { c.ping = await Pinger.ping(c); if (mounted) setState(() {}); }

  Future<void> _toggleConnect() async {
    if (_selected == null) return;
    if (_conn == ConnState.on) { setState(() => _conn = ConnState.connecting); await XrayEngine.instance.stop(); setState(() => _conn = ConnState.off); return; }
    setState(() => _conn = ConnState.connecting);
    try { await XrayEngine.instance.start(_selected!.raw); setState(() => _conn = ConnState.on); }
    catch (e) { setState(() => _conn = ConnState.off); _toast('Ошибка подключения: ' + e.toString()); }
  }

  void _openAdd() => showDialog(context: context, builder: (_) => AddDialog(onAdd: _addConfigs));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBrand)));
    Widget body;
    switch (_rail) {
      case 1:
        body = StatsPane(server: _selected, state: _conn, mode: _mode, total: _configs.length, groups: _subs.length);
        break;
      case 2:
        body = SettingsPane(mode: _mode, onMode: (md) => setState(() => _mode = md));
        break;
      case 3:
        body = const AboutPane();
        break;
      default:
        body = Row(children: [
          Expanded(child: ServersPane(
            configs: _configs, query: _query, selected: _selected, subs: _subs,
            onQuery: (q) => setState(() => _query = q),
            onSelect: _select, onRemove: _remove, onRemoveGroup: _removeGroup, onPin: _togglePin,
            onAdd: _addConfigs, onPingAll: _pingAll, onPingGroup: _pingGroup, onPingOne: _pingOne,
            onUpdateGroup: _updateGroup, onRenameGroup: _renameGroup,
          )),
          ConnectPane(server: _selected, state: _conn, mode: _mode, onToggle: _toggleConnect,
            onMode: (m) => setState(() => _mode = m), onTestPing: () { if (_selected != null) _pingOne(_selected!); }),
        ]);
    }
    return Scaffold(body: Row(children: [
      _SideRail(index: _rail, onChange: (i) => setState(() => _rail = i), onAdd: _openAdd),
      Expanded(child: body),
    ]));
  }
}

class _Glass extends StatelessWidget {
  final Widget child; const _Glass({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(8),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
      boxShadow: [BoxShadow(color: kBrand.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 8))],
    ),
    child: child,
  );
}

class StatsPane extends StatelessWidget {
  final ProxyConfig? server; final ConnState state; final RouteMode mode; final int total; final int groups;
  const StatsPane({super.key, required this.server, required this.state, required this.mode, required this.total, required this.groups});
  Widget _stat(IconData ic, String label, String val) => Expanded(child: _Glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(ic, color: kBrand, size: 26), const SizedBox(height: 14),
    Text(val, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)), const SizedBox(height: 4),
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
  ])));
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Padding(padding: EdgeInsets.fromLTRB(8, 8, 0, 4), child: Text('Статистика', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700))),
    const SizedBox(height: 12),
    Row(children: [_stat(Icons.dns_rounded, 'Серверов', '$total'), _stat(Icons.folder_rounded, 'Подписок', '$groups')]),
    Row(children: [_stat(Icons.power_settings_new_rounded, 'Статус', state == ConnState.off ? 'Выключено' : 'Подключено'), _stat(Icons.alt_route_rounded, 'Режим', mode == RouteMode.proxy ? 'Proxy' : 'TUN')]),
    _Glass(child: Row(children: [const Icon(Icons.bolt, color: kBrand), const SizedBox(width: 12), Expanded(child: Text(server == null ? 'Сервер не выбран' : server!.name, style: const TextStyle(color: Colors.white, fontSize: 15)))])),
  ]));
}

class SettingsPane extends StatelessWidget {
  final RouteMode mode; final ValueChanged<RouteMode> onMode;
  const SettingsPane({super.key, required this.mode, required this.onMode});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Padding(padding: EdgeInsets.fromLTRB(8, 8, 0, 4), child: Text('Настройки', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700))),
    const SizedBox(height: 8),
    _Glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Режим маршрутизации', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 4),
      const Text('Proxy — системный HTTP/SOCKS прокси (sing-box). TUN — захват всего трафика (скоро).', style: TextStyle(color: Colors.white54, fontSize: 13)), const SizedBox(height: 14),
      SegmentedButton<RouteMode>(segments: const [
        ButtonSegment(value: RouteMode.proxy, label: Text('Proxy'), icon: Icon(Icons.lan_rounded)),
        ButtonSegment(value: RouteMode.tun, label: Text('TUN'), icon: Icon(Icons.vpn_lock_rounded)),
      ], selected: {mode}, onSelectionChanged: (s) => onMode(s.first)),
    ])),
    const _Glass(child: Row(children: [Icon(Icons.info_outline, color: Colors.white54), SizedBox(width: 12), Expanded(child: Text('Движок sing-box: vless, vmess, trojan, shadowsocks, hysteria2, hysteria, tuic (в т.ч. Reality / WS / gRPC).', style: TextStyle(color: Colors.white60, fontSize: 13)))])),
  ]));
}

class AboutPane extends StatelessWidget {
  const AboutPane({super.key});
  @override
  Widget build(BuildContext context) => Center(child: _Glass(child: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 64, height: 64, decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: kBrand.withOpacity(.4), blurRadius: 18)]), child: const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 36)),
    const SizedBox(height: 16),
    const Text('NST Tunnel', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)), const SizedBox(height: 4),
    const Text('Desktop 2.26.0', style: TextStyle(color: Colors.white54)), const SizedBox(height: 16),
    const Text('Кросс-платформенный VPN-клиент на sing-box.\nИмпорт подписок, тест пинга, Happ-style интерфейс.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 13)),
  ]))));
}

extension IterFirst<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }

class _SideRail extends StatelessWidget {
  final int index; final ValueChanged<int> onChange; final VoidCallback onAdd;
  const _SideRail({required this.index, required this.onChange, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final items = [Icons.dns_rounded, Icons.insights_rounded, Icons.settings_rounded];
    final labels = ['Серверы', 'Статистика', 'Настройки'];
    return Container(width: 76, color: kPanel, child: Column(children: [
      const SizedBox(height: 18),
      Container(width: 44, height: 44, decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(13), boxShadow: [BoxShadow(color: kBrand.withOpacity(.45), blurRadius: 16, offset: const Offset(0, 4))]), child: const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 24)),
      const SizedBox(height: 10),
      Tooltip(message: 'Добавить', child: InkWell(onTap: onAdd, borderRadius: BorderRadius.circular(12), child: Container(width: 48, height: 40, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)), child: const Icon(Icons.add_rounded, color: Colors.white70, size: 24)))),
      const SizedBox(height: 16),
      for (int i = 0; i < items.length; i++)
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Tooltip(message: labels[i], child: InkWell(onTap: () => onChange(i), borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: 48, height: 48, decoration: BoxDecoration(color: index == i ? kBrand.withOpacity(.16) : Colors.transparent, borderRadius: BorderRadius.circular(13), border: Border.all(color: index == i ? kBrand.withOpacity(.5) : Colors.transparent)),
          child: Icon(items[i], color: index == i ? kBrand : Colors.white54, size: 23))))),
      const Spacer(),
      Tooltip(message: 'О программе', child: InkWell(onTap: () => onChange(3), borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.only(bottom: 16, top: 8), child: Icon(Icons.info_outline_rounded, color: index == 3 ? kBrand : Colors.white38, size: 21)))),
    ]));
  }
}

class ServersPane extends StatelessWidget {
  final List<ProxyConfig> configs; final List<Subscription> subs; final String query; final ProxyConfig? selected;
  final ValueChanged<String> onQuery; final ValueChanged<ProxyConfig> onSelect;
  final ValueChanged<ProxyConfig> onRemove; final ValueChanged<String> onRemoveGroup; final ValueChanged<ProxyConfig> onPin;
  final Future<void> Function(List<ProxyConfig>, {Subscription? sub}) onAdd;
  final Future<void> Function() onPingAll; final Future<void> Function(String) onPingGroup; final Future<void> Function(ProxyConfig) onPingOne;
  final Future<void> Function(String) onUpdateGroup; final Future<void> Function(String, String) onRenameGroup;
  const ServersPane({super.key, required this.configs, required this.subs, required this.query, required this.selected, required this.onQuery, required this.onSelect, required this.onRemove, required this.onRemoveGroup, required this.onPin, required this.onAdd, required this.onPingAll, required this.onPingGroup, required this.onPingOne, required this.onUpdateGroup, required this.onRenameGroup});

  Map<String, List<ProxyConfig>> get _grouped {
    final f = query.trim().toLowerCase();
    final m = <String, List<ProxyConfig>>{};
    for (final c in configs) { if (f.isEmpty || c.name.toLowerCase().contains(f) || c.group.toLowerCase().contains(f)) m.putIfAbsent(c.group, () => []).add(c); }
    for (final list in m.values) {
      list.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        final pa = a.ping == null ? 1<<30 : a.ping! < 0 ? 1<<29 : a.ping!;
        final pb = b.ping == null ? 1<<30 : b.ping! < 0 ? 1<<29 : b.ping!;
        return pa.compareTo(pb);
      });
    }
    return m;
  }

  String? _subUrlFor(String g) { for (final s in subs) { if (s.name == g) return s.url; } return null; }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    return Container(width: 470, color: kBg, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(24, 22, 24, 8), child: Text('Серверы', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
        Expanded(child: Container(height: 44, decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const SizedBox(width: 12), const Icon(Icons.search, color: Colors.white38, size: 20), const SizedBox(width: 8),
            Expanded(child: TextField(onChanged: onQuery, style: const TextStyle(fontSize: 14), decoration: const InputDecoration(hintText: 'Введите текст для поиска', hintStyle: TextStyle(color: Colors.white30), border: InputBorder.none, isDense: true))),
          ]))),
        const SizedBox(width: 6),
        IconButton(tooltip: 'Пинг всех', onPressed: onPingAll, icon: const Icon(Icons.speed, color: Colors.white54)),
        _topMenu(context),
      ])),
      const SizedBox(height: 8),
      Expanded(child: configs.isEmpty ? _empty(context) : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: groups.entries.map((e) => _GroupCard(group: e.key, items: e.value, selected: selected, hasSub: _subUrlFor(e.key) != null, subUrl: _subUrlFor(e.key),
          onSelect: onSelect, onRemove: onRemove, onRemoveGroup: onRemoveGroup, onPin: onPin, onPingGroup: onPingGroup, onPingOne: onPingOne, onUpdate: onUpdateGroup, onRename: onRenameGroup)).toList())),
    ]));
  }

  Widget _topMenu(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_horiz, color: Colors.white54), color: kSurface,
    onSelected: (v) { if (v == 'add') _showAdd(context); else if (v == 'ping') onPingAll(); },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'add', child: Row(children: [Icon(Icons.add, size: 18, color: kBrand), SizedBox(width: 10), Text('Добавить URL')])),
      PopupMenuItem(value: 'ping', child: Row(children: [Icon(Icons.speed, size: 18, color: Colors.white70), SizedBox(width: 10), Text('Пинг всех')])),
    ]);

  Widget _empty(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off, color: Colors.white24, size: 60), const SizedBox(height: 14),
    const Text('Нет конфигов', style: TextStyle(color: Colors.white70, fontSize: 17, fontWeight: FontWeight.w600)), const SizedBox(height: 16),
    FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: kBrand), onPressed: () => _showAdd(context), icon: const Icon(Icons.add), label: const Text('Добавить')),
  ]));

  void _showAdd(BuildContext context) => showDialog(context: context, builder: (_) => AddDialog(onAdd: onAdd));
}

class _GroupCard extends StatefulWidget {
  final String group; final List<ProxyConfig> items; final ProxyConfig? selected; final bool hasSub; final String? subUrl;
  final ValueChanged<ProxyConfig> onSelect; final ValueChanged<ProxyConfig> onRemove; final ValueChanged<String> onRemoveGroup; final ValueChanged<ProxyConfig> onPin;
  final Future<void> Function(String) onPingGroup; final Future<void> Function(ProxyConfig) onPingOne; final Future<void> Function(String) onUpdate; final Future<void> Function(String, String) onRename;
  const _GroupCard({required this.group, required this.items, required this.selected, required this.hasSub, required this.subUrl, required this.onSelect, required this.onRemove, required this.onRemoveGroup, required this.onPin, required this.onPingGroup, required this.onPingOne, required this.onUpdate, required this.onRename});
  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _open = true; bool _busy = false;

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: widget.group);
    final res = await showDialog<String>(context: context, builder: (_) => AlertDialog(backgroundColor: kSurface, title: const Text('Переименовать'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Название')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(style: FilledButton.styleFrom(backgroundColor: kBrand), onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK'))]));
    if (res != null) widget.onRename(widget.group, res);
  }

  @override
  Widget build(BuildContext context) {
    final pings = widget.items.map((e) => e.ping).where((p) => p != null && p > 0).cast<int>().toList();
    final best = pings.isEmpty ? null : pings.reduce((a, b) => a < b ? a : b);
    final subtitle = widget.items.length.toString() + ' servers' + (best != null ? ' · best ' + best.toString() + ' ms' : '');
    return Card(color: kSurface, margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Column(children: [
      InkWell(borderRadius: BorderRadius.circular(16), onTap: () => setState(() => _open = !_open), child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 6, 12), child: Row(children: [
        AnimatedRotation(turns: _open ? 0 : -0.25, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more, color: Colors.white60, size: 22)),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(widget.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            if (widget.hasSub) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.cloud_done, size: 14, color: kGood)),
          ]),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: best != null ? pingColor(best) : Colors.white38, fontSize: 12)),
        ])),
        if (_busy) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kBrand)))
        else _menu(),
      ]))),
      AnimatedCrossFade(duration: const Duration(milliseconds: 200), crossFadeState: _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        firstChild: Column(children: widget.items.map((s) => _ServerRow(s: s, selected: s == widget.selected, onSelect: widget.onSelect, onRemove: widget.onRemove, onPin: widget.onPin, onPing: widget.onPingOne)).toList()),
        secondChild: const SizedBox(width: double.infinity)),
    ]));
  }

  Widget _menu() => PopupMenuButton<String>(icon: const Icon(Icons.more_horiz, color: Colors.white54, size: 20), color: kSurface2,
    onSelected: (v) async {
      if (v == 'update') { setState(() => _busy = true); await widget.onUpdate(widget.group); if (mounted) setState(() => _busy = false); }
      else if (v == 'ping') { setState(() => _busy = true); await widget.onPingGroup(widget.group); if (mounted) setState(() => _busy = false); }
      else if (v == 'copy') { if (widget.subUrl != null) await Clipboard.setData(ClipboardData(text: widget.subUrl!)); }
      else if (v == 'rename') { await _rename(); }
      else if (v == 'delete') { widget.onRemoveGroup(widget.group); }
    },
    itemBuilder: (_) => [
      if (widget.hasSub) const PopupMenuItem(value: 'update', child: Row(children: [Icon(Icons.refresh, size: 18, color: kBrand), SizedBox(width: 10), Text('Обновить')])),
      const PopupMenuItem(value: 'ping', child: Row(children: [Icon(Icons.speed, size: 18, color: Colors.white70), SizedBox(width: 10), Text('Тест пинга')])),
      if (widget.subUrl != null) const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy, size: 18, color: Colors.white70), SizedBox(width: 10), Text('Копировать URL')])),
      const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 18, color: Colors.white70), SizedBox(width: 10), Text('Редактировать')])),
      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: kBad), SizedBox(width: 10), Text('Удалить')])),
    ]);
}

class _ServerRow extends StatelessWidget {
  final ProxyConfig s; final bool selected; final ValueChanged<ProxyConfig> onSelect; final ValueChanged<ProxyConfig> onRemove; final ValueChanged<ProxyConfig> onPin; final Future<void> Function(ProxyConfig) onPing;
  const _ServerRow({required this.s, required this.selected, required this.onSelect, required this.onRemove, required this.onPin, required this.onPing});
  @override
  Widget build(BuildContext context) {
    final sub = s.protocol.toUpperCase() + ' / ' + s.transport;
    return InkWell(onTap: () => onSelect(s), child: Container(
      decoration: BoxDecoration(color: selected ? kBrand.withOpacity(0.10) : Colors.transparent, border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
      child: Row(children: [
        Text(s.flag, style: const TextStyle(fontSize: 20)), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            if (s.pinned) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.push_pin, size: 12, color: kBrand)),
            Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          ]),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ])),
        Icon(Icons.circle, size: 7, color: pingColor(s.ping)), const SizedBox(width: 5),
        SizedBox(width: 56, child: Text(pingLabel(s.ping), textAlign: TextAlign.right, style: TextStyle(color: pingColor(s.ping), fontSize: 11, fontWeight: FontWeight.w600))),
        PopupMenuButton<String>(icon: const Icon(Icons.chevron_right, color: Colors.white38, size: 20), color: kSurface2,
          onSelected: (v) { if (v == 'ping') onPing(s); else if (v == 'pin') onPin(s); else if (v == 'copy') Clipboard.setData(ClipboardData(text: s.raw)); else if (v == 'delete') onRemove(s); },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'ping', child: Row(children: [Icon(Icons.speed, size: 18, color: Colors.white70), SizedBox(width: 10), Text('Тест пинга')])),
            PopupMenuItem(value: 'pin', child: Row(children: [const Icon(Icons.push_pin, size: 18, color: kBrand), const SizedBox(width: 10), Text(s.pinned ? 'Открепить' : 'Закрепить')])),
            const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy, size: 18, color: Colors.white70), SizedBox(width: 10), Text('Копировать URL')])),
            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: kBad), SizedBox(width: 10), Text('Удалить')])),
          ]),
      ]),
    ));
  }
}

class ConnectPane extends StatefulWidget {
  final ProxyConfig? server; final ConnState state; final RouteMode mode; final VoidCallback onToggle; final ValueChanged<RouteMode> onMode; final VoidCallback onTestPing;
  const ConnectPane({super.key, required this.server, required this.state, required this.mode, required this.onToggle, required this.onMode, required this.onTestPing});
  @override
  State<ConnectPane> createState() => _ConnectPaneState();
}

class _ConnectPaneState extends State<ConnectPane> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  Timer? _timer; int _seconds = 0;
  @override
  void didUpdateWidget(ConnectPane old) {
    super.didUpdateWidget(old);
    if (widget.state == ConnState.on && _timer == null) { _seconds = 0; _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++)); }
    if (widget.state != ConnState.on && _timer != null) { _timer!.cancel(); _timer = null; _seconds = 0; }
  }
  @override
  void dispose() { _timer?.cancel(); _pulse.dispose(); super.dispose(); }
  String get _elapsed { final h=(_seconds~/3600).toString().padLeft(2,'0'); final mm=((_seconds%3600)~/60).toString().padLeft(2,'0'); final ss=(_seconds%60).toString().padLeft(2,'0'); return h + ':' + mm + ':' + ss; }

  @override
  Widget build(BuildContext context) {
    final srv = widget.server; final on = widget.state == ConnState.on; final connecting = widget.state == ConnState.connecting;
    final status = on ? 'Защищено' : connecting ? 'Подключение…' : srv == null ? 'Нет сервера' : 'Отключено';
    return Container(width: 360, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kPanel, kBg])),
      child: Column(children: [
        const SizedBox(height: 48),
        GestureDetector(onTap: connecting ? null : widget.onToggle, child: AnimatedBuilder(animation: _pulse, builder: (context, _) {
          final glow = on ? (0.35 + _pulse.value * 0.35) : (0.18 + _pulse.value * 0.12);
          final core = on ? const Color(0xFF3D9B74) : kBrandDim;
          final edge = on ? kGood : kAccentBlue;
          return Container(width: 210, height: 210, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [core, kPanel], radius: 0.95),
            boxShadow: [
              BoxShadow(color: edge.withOpacity(glow), blurRadius: 52, spreadRadius: 4),
              BoxShadow(color: edge.withOpacity(glow * 0.35), blurRadius: 80, spreadRadius: 12),
            ],
            border: Border.all(color: edge.withOpacity(0.55), width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 72),
              const SizedBox(height: 6),
              Text(on ? 'ON' : connecting ? '...' : 'OFF', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 2)),
            ]));
        })),
        const SizedBox(height: 20),
        Text(status, style: TextStyle(color: on ? kGood : connecting ? kBrand : Colors.white54, fontSize: 18, fontWeight: FontWeight.w700)),
        if (on) Text(_elapsed, style: const TextStyle(color: Colors.white38, fontFeatures: [FontFeature.tabularFigures()])),
        const Spacer(),
        if (srv != null) Column(children: [
          Text(srv.flag, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 6),
          Text(srv.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(width: 200, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kAccentBlue, padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: widget.onTestPing,
            child: Text(srv.ping == null ? 'Тест пинга' : 'Пинг: ' + pingLabel(srv.ping), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))),
        ]),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [
          _modeBtn('Proxy', RouteMode.proxy), _modeBtn('TUN', RouteMode.tun),
        ])),
        const SizedBox(height: 28),
      ]));
  }

  Widget _modeBtn(String label, RouteMode m) {
    final active = widget.mode == m;
    return GestureDetector(onTap: () => widget.onMode(m), child: AnimatedContainer(duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(color: active ? kAccentBlue : Colors.transparent, borderRadius: BorderRadius.circular(9)),
      child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontWeight: FontWeight.w700, fontSize: 13))));
  }
}

class AddDialog extends StatefulWidget {
  final Future<void> Function(List<ProxyConfig>, {Subscription? sub}) onAdd;
  const AddDialog({super.key, required this.onAdd});
  @override
  State<AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<AddDialog> {
  final _link = TextEditingController(); final _url = TextEditingController(); final _name = TextEditingController();
  bool _busy = false; String? _error;

  Future<void> _importLinks() async {
    final t = _link.text.trim(); if (t.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    final g = _name.text.trim().isEmpty ? 'Manual' : _name.text.trim();
    final cfgs = ConfigParser.parseMany(ConfigParser.normalizeBody(t), g);
    setState(() => _busy = false);
    if (cfgs.isEmpty) { setState(() => _error = 'Конфиги не найдены'); return; }
    await widget.onAdd(cfgs); if (mounted) Navigator.pop(context);
  }

  Future<void> _importSub() async {
    final u = _url.text.trim(); if (u.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final body = await SubscriptionFetcher.fetch(u);
      final g = _name.text.trim().isNotEmpty ? _name.text.trim() : (Uri.tryParse(u)?.host ?? 'Subscription');
      final cfgs = ConfigParser.parseMany(body, g);
      setState(() => _busy = false);
      if (cfgs.isEmpty) { setState(() => _error = 'В подписке нет конфигов'); return; }
      await widget.onAdd(cfgs, sub: Subscription(name: g, url: u));
      if (mounted) Navigator.pop(context);
    } catch (e) { setState(() { _busy = false; _error = 'Ошибка: ' + e.toString(); }); }
  }

  @override
  void dispose() { _link.dispose(); _url.dispose(); _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Dialog(backgroundColor: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540), child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(26), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Добавить конфиг', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)), const SizedBox(height: 18),
        TextField(controller: _name, style: const TextStyle(fontSize: 13), decoration: _dec('Название подписки (необязательно)')), const SizedBox(height: 18),
        const Text('Вставить ссылку(и)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
        TextField(controller: _link, maxLines: 4, style: const TextStyle(fontSize: 13), decoration: _dec('vless://...  vmess://...  trojan://...  ss://...')), const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kBrandDim), onPressed: _busy ? null : _importLinks, child: const Text('Импорт ссылок'))),
        const SizedBox(height: 10), Divider(color: Colors.white.withOpacity(0.08)), const SizedBox(height: 10),
        const Text('Или подписка по URL', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
        TextField(controller: _url, style: const TextStyle(fontSize: 13), decoration: _dec('https://example.com/sub/...')), const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: kBrand), onPressed: _busy ? null : _importSub, icon: const Icon(Icons.cloud_download, size: 18), label: const Text('Загрузить'))),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator(color: kBrand))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kBad))),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть', style: TextStyle(color: Colors.white54)))),
      ])))));
  }
  InputDecoration _dec(String h) => InputDecoration(hintText: h, hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: kBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none));
}