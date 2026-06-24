import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'xray_engine.dart';

void main() => runApp(const NstTunnelApp());

const kBrand = Color(0xFFF97910);
const kBrandDim = Color(0xFFB85A0B);
const kBg = Color(0xFF131114);
const kSurface = Color(0xFF1C1A1E);
const kSurface2 = Color(0xFF242128);
const kGood = Color(0xFF34C759);
const kWarn = Color(0xFFFFB02E);
const kBad = Color(0xFFE5484D);

// ---------------- Model ----------------
class ProxyConfig {
  final String protocol, name, address, group, raw;
  final int port;
  int? ping; // ms, null = unknown, -1 = timeout
  ProxyConfig({required this.protocol, required this.name, required this.address, required this.port, required this.group, required this.raw, this.ping});

  Map<String, dynamic> toJson() => {'raw': raw, 'group': group};
  String get flag => _flagFor(name);
}

String _flagFor(String s) {
  final t = s.toLowerCase();
  const map = {
    '🇳🇱': ['nether','amsterdam','🇳🇱'], '🇩🇪': ['german','frankfurt','🇩🇪'],
    '🇺🇸': ['usa','united states','🇺🇸'], '🇬🇧': ['london','🇬🇧'],
    '🇫🇷': ['france','paris','🇫🇷'], '🇯🇵': ['japan','tokyo','🇯🇵'],
    '🇸🇬': ['singapore','🇸🇬'], '🇷🇺': ['russia','moscow','🇷🇺'],
    '🇫🇮': ['finland','🇫🇮'], '🇸🇪': ['sweden','🇸🇪'], '🇳🇱':['nl'],
    '🇹🇷': ['turkey','istanbul','🇹🇷'], '🇦🇪': ['emirat','dubai','🇦🇪'],
  };
  for (final e in map.entries) { for (final k in e.value) { if (t.contains(k)) return e.key; } }
  return '🌐';
}

// ---------------- Parsing ----------------
class ConfigParser {
  static String normalizeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.contains('://')) return trimmed;
    try {
      final fixed = base64.normalize(trimmed.replaceAll(RegExp(r'\s'), ''));
      final decoded = utf8.decode(base64.decode(fixed), allowMalformed: true);
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    return trimmed;
  }

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

  static ProxyConfig? parseOne(String link, String group) {
    try {
      if (link.startsWith('vmess://')) return _vmess(link, group);
      if (link.startsWith('vless://')) return _generic(link, 'vless', group);
      if (link.startsWith('trojan://')) return _generic(link, 'trojan', group);
      if (link.startsWith('ss://')) return _ss(link, group);
    } catch (_) {}
    return null;
  }

  static String _tag(Uri u) { if (u.fragment.isEmpty) return ''; try { return Uri.decodeComponent(u.fragment); } catch (_) { return u.fragment; } }

  static ProxyConfig _generic(String link, String proto, String group) {
    final u = Uri.parse(link);
    final name = _tag(u);
    return ProxyConfig(protocol: proto, name: name.isEmpty ? '$proto ${u.host}' : name, address: u.host, port: u.port == 0 ? 443 : u.port, group: group, raw: link);
  }
  static ProxyConfig _vmess(String link, String group) {
    final j = jsonDecode(utf8.decode(base64.decode(base64.normalize(link.substring(8)))));
    final name = (j['ps'] ?? '').toString();
    final host = (j['add'] ?? '').toString();
    final port = int.tryParse((j['port'] ?? '443').toString()) ?? 443;
    return ProxyConfig(protocol: 'vmess', name: name.isEmpty ? 'vmess $host' : name, address: host, port: port, group: group, raw: link);
  }
  static ProxyConfig _ss(String link, String group) {
    final u = Uri.parse(link);
    final name = _tag(u);
    String host = u.host; int port = u.port;
    if (host.isEmpty) {
      final body = link.substring(5).split('#').first;
      final dec = utf8.decode(base64.decode(base64.normalize(body)), allowMalformed: true);
      final at = dec.lastIndexOf('@');
      if (at != -1) { final hp = dec.substring(at+1).split(':'); host = hp.first; port = int.tryParse(hp.length>1?hp[1]:'443') ?? 443; }
    }
    if (port == 0) port = 443;
    return ProxyConfig(protocol: 'ss', name: name.isEmpty ? 'ss $host' : name, address: host, port: port, group: group, raw: link);
  }
}

// ---------------- Ping (GET/HEAD + TCP fallback) ----------------
class Pinger {
  /// Measure latency: try HTTP HEAD, else TCP connect time. Returns ms or -1.
  static Future<int> ping(ProxyConfig c) async {
    final sw = Stopwatch()..start();
    // 1) TCP connect latency (works for any proxy node, like Happ's real ping)
    try {
      final socket = await Socket.connect(c.address, c.port, timeout: const Duration(seconds: 4));
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {}
    // 2) Fallback: HTTP HEAD on standard ports
    try {
      sw..reset()..start();
      final client = http.Client();
      final scheme = c.port == 80 ? 'http' : 'https';
      await client.head(Uri.parse('$scheme://${c.address}:${c.port}')).timeout(const Duration(seconds: 4));
      sw.stop();
      client.close();
      return sw.elapsedMilliseconds;
    } catch (_) {}
    return -1;
  }
}

// ---------------- Storage ----------------
class ConfigStore {
  static const _key = 'nst_configs_v2';
  static const _legacy = 'nst_configs_v1';
  static Future<List<ProxyConfig>> load() async {
    final p = await SharedPreferences.getInstance();
    final list = <ProxyConfig>[];
    final v2 = p.getStringList(_key);
    if (v2 != null) {
      for (final s in v2) {
        try { final j = jsonDecode(s); final c = ConfigParser.parseOne(j['raw'], j['group'] ?? 'Imported'); if (c != null) list.add(c); } catch (_) {}
      }
      return list;
    }
    final v1 = p.getStringList(_legacy);
    if (v1 != null) { for (final r in v1) { final c = ConfigParser.parseOne(r, 'Imported'); if (c != null) list.add(c); } }
    return list;
  }
  static Future<void> save(List<ProxyConfig> cfgs) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, cfgs.map((c) => jsonEncode(c.toJson())).toList());
  }
}

// ---------------- App ----------------
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  List<ProxyConfig> _configs = [];
  ProxyConfig? _selected;
  bool _loading = true;
  ConnState _conn = ConnState.off;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await ConfigStore.load();
    setState(() { _configs = list; _selected = list.isNotEmpty ? list.first : null; _loading = false; });
  }
  Future<void> _persist() async => ConfigStore.save(_configs);

  Future<void> _addConfigs(List<ProxyConfig> added) async {
    if (added.isEmpty) return;
    final existing = _configs.map((e) => e.raw).toSet();
    final fresh = added.where((c) => !existing.contains(c.raw)).toList();
    setState(() { _configs = [..._configs, ...fresh]; _selected ??= _configs.isNotEmpty ? _configs.first : null; });
    await _persist();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${fresh.length} config(s)'), backgroundColor: kBrandDim));
  }

  Future<void> _remove(ProxyConfig c) async {
    setState(() { _configs.remove(c); if (_selected == c) _selected = _configs.isNotEmpty ? _configs.first : null; });
    await _persist();
  }
  void _removeGroup(String g) async {
    setState(() { _configs.removeWhere((c) => c.group == g); if (_selected != null && !_configs.contains(_selected)) _selected = _configs.isNotEmpty ? _configs.first : null; });
    await _persist();
  }
  void _select(ProxyConfig c) => setState(() { _selected = c; });

  Future<void> _pingAll() async {
    final futures = _configs.map((c) async { c.ping = await Pinger.ping(c); if (mounted) setState(() {}); });
    await Future.wait(futures);
  }
  Future<void> _pingGroup(String g) async {
    final futures = _configs.where((c) => c.group == g).map((c) async { c.ping = await Pinger.ping(c); if (mounted) setState(() {}); });
    await Future.wait(futures);
  }

  Future<void> _toggleConnect() async {
    if (_selected == null) return;
    if (_conn == ConnState.on) {
      setState(() => _conn = ConnState.connecting);
      await XrayEngine.instance.stop();
      setState(() => _conn = ConnState.off);
      return;
    }
    setState(() => _conn = ConnState.connecting);
    try {
      await XrayEngine.instance.start(_selected!.raw);
      setState(() => _conn = ConnState.on);
    } catch (e) {
      setState(() => _conn = ConnState.off);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connect failed: $e'), backgroundColor: kBad));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBrand)));
    final pages = [
      ConnectPage(server: _selected, state: _conn, onToggle: _toggleConnect),
      ServersPage(configs: _configs, selected: _selected, onSelect: _select, onRemove: _remove, onRemoveGroup: _removeGroup, onAdd: _addConfigs, onPingAll: _pingAll, onPingGroup: _pingGroup),
      const SettingsPage(),
    ];
    return Scaffold(body: Row(children: [
      _SideRail(index: _index, onChange: (i) => setState(() => _index = i)),
      Container(width: 1, color: Colors.white.withOpacity(0.06)),
      Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: Container(key: ValueKey(_index), child: pages[_index]))),
    ]));
  }
}

class _SideRail extends StatelessWidget {
  final int index; final ValueChanged<int> onChange;
  const _SideRail({required this.index, required this.onChange});
  @override
  Widget build(BuildContext context) {
    final items = [(Icons.shield_outlined, Icons.shield, 'Connect'), (Icons.dns_outlined, Icons.dns, 'Servers'), (Icons.settings_outlined, Icons.settings, 'Settings')];
    return Container(width: 92, color: kSurface, child: Column(children: [
      const SizedBox(height: 28),
      Container(width: 46, height: 46, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kBrand, kBrandDim]), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.bolt, color: Colors.white, size: 26)),
      const SizedBox(height: 6),
      const Text('NST', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
      const SizedBox(height: 32),
      for (int i = 0; i < items.length; i++) _RailButton(icon: index == i ? items[i].$2 : items[i].$1, label: items[i].$3, active: index == i, onTap: () => onChange(i)),
      const Spacer(),
      const Padding(padding: EdgeInsets.only(bottom: 16), child: Text('v2.18.0', style: TextStyle(color: Colors.white38, fontSize: 11))),
    ]));
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  const _RailButton({required this.icon, required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: active ? kBrand.withOpacity(0.16) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [Icon(icon, color: active ? kBrand : Colors.white60, size: 24), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 11, color: active ? kBrand : Colors.white60))]))));
  }
}

enum ConnState { off, connecting, on }

Color pingColor(int? ms) {
  if (ms == null) return Colors.white38;
  if (ms < 0) return kBad;
  if (ms < 150) return kGood;
  if (ms < 350) return kWarn;
  return kBad;
}
String pingLabel(int? ms) => ms == null ? '—' : ms < 0 ? 'timeout' : '$ms ms';

class ConnectPage extends StatefulWidget {
  final ProxyConfig? server; final ConnState state; final VoidCallback onToggle;
  const ConnectPage({super.key, required this.server, required this.state, required this.onToggle});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> with SingleTickerProviderStateMixin {
  Timer? _timer; int _seconds = 0;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void didUpdateWidget(ConnectPage old) {
    super.didUpdateWidget(old);
    if (widget.state == ConnState.on && _timer == null) { _seconds = 0; _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++)); }
    if (widget.state != ConnState.on && _timer != null) { _timer!.cancel(); _timer = null; _seconds = 0; }
  }
  @override
  void dispose() { _timer?.cancel(); _pulse.dispose(); super.dispose(); }

  String get _elapsed { final h=(_seconds~/3600).toString().padLeft(2,'0'); final m=((_seconds%3600)~/60).toString().padLeft(2,'0'); final s=(_seconds%60).toString().padLeft(2,'0'); return '$h:$m:$s'; }

  @override
  Widget build(BuildContext context) {
    final srv = widget.server;
    final on = widget.state == ConnState.on;
    final connecting = widget.state == ConnState.connecting;
    final statusText = srv == null ? 'No server — import a config' : on ? 'Protected' : connecting ? 'Connecting…' : 'Not connected';
    final statusColor = on ? kGood : connecting ? kBrand : Colors.white54;
    return Padding(padding: const EdgeInsets.all(40), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Dashboard', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Your secure tunnel at a glance', style: TextStyle(color: Colors.white.withOpacity(0.5))),
      const Spacer(),
      Center(child: GestureDetector(onTap: connecting ? null : widget.onToggle, child: AnimatedBuilder(animation: _pulse, builder: (context, _) {
        final glow = on ? (0.25 + _pulse.value * 0.25) : 0.12;
        return Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: on ? [kGood, const Color(0xFF1E9E48)] : [kBrand, kBrandDim]),
          boxShadow: [BoxShadow(color: (on ? kGood : kBrand).withOpacity(glow), blurRadius: 50, spreadRadius: 8)]),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(on ? Icons.lock : Icons.power_settings_new, color: Colors.white, size: 64), const SizedBox(height: 10),
            Text(on ? 'TAP TO STOP' : connecting ? 'WAIT' : 'TAP TO CONNECT', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 13))]));
      }))),
      const SizedBox(height: 28),
      Center(child: Column(children: [Text(statusText, style: TextStyle(color: statusColor, fontSize: 20, fontWeight: FontWeight.w700)),
        if (on) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_elapsed, style: const TextStyle(color: Colors.white54, fontFeatures: [FontFeature.tabularFigures()])))])),
      const Spacer(),
      if (srv != null) Row(children: [
        Expanded(child: _StatCard(icon: Icons.public, label: 'Server', value: '${srv.flag}  ${srv.name}')),
        const SizedBox(width: 16),
        Expanded(child: _StatCard(icon: Icons.lan, label: 'Address', value: '${srv.address}:${srv.port}')),
        const SizedBox(width: 16),
        Expanded(child: _StatCard(icon: Icons.vpn_key, label: 'Protocol', value: srv.protocol.toUpperCase())),
      ]),
    ]));
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String label; final String value;
  const _StatCard({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Card(color: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: kBrand, size: 22), const SizedBox(height: 14),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)), const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))])));
  }
}

class ServersPage extends StatelessWidget {
  final List<ProxyConfig> configs; final ProxyConfig? selected;
  final ValueChanged<ProxyConfig> onSelect; final ValueChanged<ProxyConfig> onRemove;
  final ValueChanged<String> onRemoveGroup; final Future<void> Function(List<ProxyConfig>) onAdd;
  final Future<void> Function() onPingAll; final Future<void> Function(String) onPingGroup;
  const ServersPage({super.key, required this.configs, required this.selected, required this.onSelect, required this.onRemove, required this.onRemoveGroup, required this.onAdd, required this.onPingAll, required this.onPingGroup});

  Map<String, List<ProxyConfig>> get _grouped {
    final m = <String, List<ProxyConfig>>{};
    for (final c in configs) { m.putIfAbsent(c.group, () => []).add(c); }
    // sort each group ascending by ping (unknown last)
    for (final list in m.values) {
      list.sort((a, b) {
        final pa = a.ping == null ? 1 << 30 : a.ping! < 0 ? (1 << 29) : a.ping!;
        final pb = b.ping == null ? 1 << 30 : b.ping! < 0 ? (1 << 29) : b.ping!;
        return pa.compareTo(pb);
      });
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    return Scaffold(backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(backgroundColor: kBrand, icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)), onPressed: () => _showAddDialog(context)),
      body: Padding(padding: const EdgeInsets.all(40), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Servers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (configs.isNotEmpty) OutlinedButton.icon(onPressed: onPingAll, icon: const Icon(Icons.network_check, size: 18, color: kBrand), label: const Text('Ping all', style: TextStyle(color: kBrand)), style: OutlinedButton.styleFrom(side: const BorderSide(color: kBrandDim))),
        ]),
        const SizedBox(height: 4),
        Text('Subscriptions are collapsible · sorted by lowest ping', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        const SizedBox(height: 20),
        Expanded(child: configs.isEmpty ? _EmptyState(onAdd: () => _showAddDialog(context))
          : ListView(children: groups.entries.map((e) => _GroupTile(group: e.key, items: e.value, selected: selected, onSelect: onSelect, onRemove: onRemove, onRemoveGroup: onRemoveGroup, onPingGroup: onPingGroup)).toList())),
      ])));
  }

  void _showAddDialog(BuildContext context) => showDialog(context: context, builder: (_) => _AddDialog(onAdd: onAdd));
}

class _GroupTile extends StatefulWidget {
  final String group; final List<ProxyConfig> items; final ProxyConfig? selected;
  final ValueChanged<ProxyConfig> onSelect; final ValueChanged<ProxyConfig> onRemove;
  final ValueChanged<String> onRemoveGroup; final Future<void> Function(String) onPingGroup;
  const _GroupTile({required this.group, required this.items, required this.selected, required this.onSelect, required this.onRemove, required this.onRemoveGroup, required this.onPingGroup});
  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _open = true; bool _pinging = false;
  @override
  Widget build(BuildContext context) {
    final pings = widget.items.map((e) => e.ping).where((p) => p != null && p > 0).cast<int>().toList();
    final best = pings.isEmpty ? null : pings.reduce((a, b) => a < b ? a : b);
    return Card(color: kSurface, margin: const EdgeInsets.only(bottom: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        InkWell(borderRadius: BorderRadius.circular(20), onTap: () => setState(() => _open = !_open),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), child: Row(children: [
            AnimatedRotation(turns: _open ? 0.25 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.chevron_right, color: Colors.white60)),
            const SizedBox(width: 8),
            const Icon(Icons.folder_outlined, color: kBrand, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(10)),
              child: Text('${widget.items.length}', style: const TextStyle(color: Colors.white60, fontSize: 12))),
            if (best != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text('best $best ms', style: TextStyle(color: pingColor(best), fontSize: 12, fontWeight: FontWeight.w600))),
            IconButton(tooltip: 'Ping group', icon: _pinging ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kBrand)) : const Icon(Icons.network_check, color: Colors.white54, size: 20),
              onPressed: _pinging ? null : () async { setState(() => _pinging = true); await widget.onPingGroup(widget.group); if (mounted) setState(() => _pinging = false); }),
            IconButton(tooltip: 'Remove subscription', icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20), onPressed: () => widget.onRemoveGroup(widget.group)),
          ]))),
        AnimatedCrossFade(duration: const Duration(milliseconds: 200), crossFadeState: _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Column(children: widget.items.map((s) => _ServerRow(s: s, selected: s == widget.selected, onSelect: widget.onSelect, onRemove: widget.onRemove)).toList()),
          secondChild: const SizedBox(width: double.infinity)),
      ]));
  }
}

class _ServerRow extends StatelessWidget {
  final ProxyConfig s; final bool selected; final ValueChanged<ProxyConfig> onSelect; final ValueChanged<ProxyConfig> onRemove;
  const _ServerRow({required this.s, required this.selected, required this.onSelect, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: () => onSelect(s), child: Container(
      decoration: BoxDecoration(color: selected ? kBrand.withOpacity(0.10) : Colors.transparent, border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Row(children: [
        Text(s.flag, style: const TextStyle(fontSize: 22)), const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${s.protocol.toUpperCase()} · ${s.address}:${s.port}', style: const TextStyle(color: Colors.white54, fontSize: 12))])),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: pingColor(s.ping)), const SizedBox(width: 6),
          SizedBox(width: 64, child: Text(pingLabel(s.ping), textAlign: TextAlign.right, style: TextStyle(color: pingColor(s.ping), fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? kBrand : Colors.white24, size: 20),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 18), onPressed: () => onRemove(s)),
        ]),
      ])));
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off, color: Colors.white24, size: 64), const SizedBox(height: 16),
      const Text('No configs yet', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(height: 6),
      Text('Add a link or import a subscription to get started', style: TextStyle(color: Colors.white.withOpacity(0.4))), const SizedBox(height: 20),
      FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: kBrand), onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add config')),
    ]));
  }
}

class _AddDialog extends StatefulWidget {
  final Future<void> Function(List<ProxyConfig>) onAdd;
  const _AddDialog({required this.onAdd});
  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _linkCtrl = TextEditingController();
  final _subCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _busy = false; String? _error;

  Future<void> _importLinks() async {
    final text = _linkCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    final group = _nameCtrl.text.trim().isEmpty ? 'Manual' : _nameCtrl.text.trim();
    final configs = ConfigParser.parseMany(ConfigParser.normalizeBody(text), group);
    setState(() => _busy = false);
    if (configs.isEmpty) { setState(() => _error = 'No valid configs found'); return; }
    await widget.onAdd(configs);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _importSubscription() async {
    final url = _subCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) { setState(() { _busy = false; _error = 'HTTP ${resp.statusCode}'; }); return; }
      final group = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : (Uri.tryParse(url)?.host ?? 'Subscription');
      final configs = ConfigParser.parseMany(ConfigParser.normalizeBody(resp.body), group);
      setState(() => _busy = false);
      if (configs.isEmpty) { setState(() => _error = 'No configs in subscription'); return; }
      await widget.onAdd(configs);
      if (mounted) Navigator.pop(context);
    } catch (e) { setState(() { _busy = false; _error = 'Failed: $e'; }); }
  }

  @override
  void dispose() { _linkCtrl.dispose(); _subCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(backgroundColor: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540), child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add config', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 18),
          TextField(controller: _nameCtrl, style: const TextStyle(fontSize: 13), decoration: _dec('Subscription name (optional)')), const SizedBox(height: 18),
          const Text('Paste link(s)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
          TextField(controller: _linkCtrl, maxLines: 4, style: const TextStyle(fontSize: 13), decoration: _dec('vless://...  vmess://...  trojan://...  ss://...')), const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kBrandDim), onPressed: _busy ? null : _importLinks, child: const Text('Import links'))),
          const SizedBox(height: 12), Divider(color: Colors.white.withOpacity(0.08)), const SizedBox(height: 12),
          const Text('Or import a subscription URL', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
          TextField(controller: _subCtrl, style: const TextStyle(fontSize: 13), decoration: _dec('https://example.com/sub.txt')), const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: kBrand), onPressed: _busy ? null : _importSubscription, icon: const Icon(Icons.cloud_download, size: 18), label: const Text('Fetch & import'))),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator(color: kBrand))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kBad))),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.white54)))),
        ])))));
  }
  InputDecoration _dec(String hint) => InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: kBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoConnect = true; bool _killSwitch = false; bool _startup = false;
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(40), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), const SizedBox(height: 24),
      Card(color: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: Column(children: [
        _toggle('Auto-connect on launch', 'Connect to last server automatically', _autoConnect, (v) => setState(() => _autoConnect = v)), _divider(),
        _toggle('Kill switch', 'Block traffic if the tunnel drops', _killSwitch, (v) => setState(() => _killSwitch = v)), _divider(),
        _toggle('Launch at startup', 'Open NST Tunnel when the system starts', _startup, (v) => setState(() => _startup = v)),
      ])),
      const SizedBox(height: 24),
      Card(color: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: const ListTile(leading: Icon(Icons.info_outline, color: kBrand), title: Text('About'), subtitle: Text('NST Tunnel desktop · v2.18.0 · Xray proxy-mode · Material 3'))),
    ]));
  }
  Widget _divider() => Divider(height: 1, color: Colors.white.withOpacity(0.06));
  Widget _toggle(String t, String s, bool v, ValueChanged<bool> on) => SwitchListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), activeColor: kBrand,
    title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(s, style: const TextStyle(color: Colors.white54)), value: v, onChanged: on);
}
