import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NstTunnelApp());

const kBrand = Color(0xFFF97910);
const kBrandDim = Color(0xFFB85A0B);
const kBg = Color(0xFF131114);
const kSurface = Color(0xFF1C1A1E);
const kGood = Color(0xFF34C759);
const kBad = Color(0xFFE5484D);

// ---------------- Model ----------------
class ProxyConfig {
  final String protocol; // vless / vmess / trojan / ss
  final String name;
  final String address;
  final int port;
  final String raw;
  const ProxyConfig({
    required this.protocol,
    required this.name,
    required this.address,
    required this.port,
    required this.raw,
  });

  Map<String, dynamic> toJson() => {'raw': raw};

  String get flag => _flagFor(name);
}

String _flagFor(String s) {
  final t = s.toLowerCase();
  if (t.contains('🇳🇱') || t.contains('nether') || t.contains('amsterdam')) return '🇳🇱';
  if (t.contains('🇩🇪') || t.contains('german') || t.contains('frankfurt')) return '🇩🇪';
  if (t.contains('🇺🇸') || t.contains('usa') || t.contains('united states')) return '🇺🇸';
  if (t.contains('🇬🇧') || t.contains('uk') || t.contains('london')) return '🇬🇧';
  if (t.contains('🇫🇷') || t.contains('france') || t.contains('paris')) return '🇫🇷';
  if (t.contains('🇯🇵') || t.contains('japan') || t.contains('tokyo')) return '🇯🇵';
  if (t.contains('🇸🇬') || t.contains('singapore')) return '🇸🇬';
  if (t.contains('🇷🇺') || t.contains('russia') || t.contains('moscow')) return '🇷🇺';
  if (t.contains('🇫🇮') || t.contains('finland')) return '🇫🇮';
  if (t.contains('🇸🇪') || t.contains('sweden')) return '🇸🇪';
  return '🌐';
}

// ---------------- Parsing ----------------
class ConfigParser {
  /// Decode possibly base64 text; returns plain text containing links.
  static String normalizeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.contains('://')) return trimmed; // already plain links
    try {
      final fixed = base64.normalize(trimmed.replaceAll(RegExp(r'\s'), ''));
      final decoded = utf8.decode(base64.decode(fixed), allowMalformed: true);
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    return trimmed;
  }

  static List<ProxyConfig> parseMany(String text) {
    final out = <ProxyConfig>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final c = parseOne(l);
      if (c != null) out.add(c);
    }
    return out;
  }

  static ProxyConfig? parseOne(String link) {
    try {
      if (link.startsWith('vmess://')) return _vmess(link);
      if (link.startsWith('vless://')) return _generic(link, 'vless');
      if (link.startsWith('trojan://')) return _generic(link, 'trojan');
      if (link.startsWith('ss://')) return _ss(link);
    } catch (_) {}
    return null;
  }

  static String _decodeTag(Uri uri) {
    final frag = uri.fragment;
    if (frag.isEmpty) return '';
    try { return Uri.decodeComponent(frag); } catch (_) { return frag; }
  }

  static ProxyConfig _generic(String link, String proto) {
    final uri = Uri.parse(link);
    final name = _decodeTag(uri);
    final host = uri.host;
    final port = uri.port == 0 ? 443 : uri.port;
    return ProxyConfig(
      protocol: proto,
      name: name.isEmpty ? '$proto $host' : name,
      address: host,
      port: port,
      raw: link,
    );
  }

  static ProxyConfig _vmess(String link) {
    final b = link.substring('vmess://'.length);
    final json = jsonDecode(utf8.decode(base64.decode(base64.normalize(b))));
    final host = (json['add'] ?? '').toString();
    final port = int.tryParse((json['port'] ?? '443').toString()) ?? 443;
    final name = (json['ps'] ?? '').toString();
    return ProxyConfig(
      protocol: 'vmess',
      name: name.isEmpty ? 'vmess $host' : name,
      address: host,
      port: port,
      raw: link,
    );
  }

  static ProxyConfig _ss(String link) {
    final uri = Uri.parse(link);
    final name = _decodeTag(uri);
    String host = uri.host;
    int port = uri.port;
    if (host.isEmpty) {
      // ss://base64(method:pass@host:port)
      final body = link.substring('ss://'.length).split('#').first;
      final decoded = utf8.decode(base64.decode(base64.normalize(body)), allowMalformed: true);
      final at = decoded.lastIndexOf('@');
      if (at != -1) {
        final hp = decoded.substring(at + 1).split(':');
        host = hp.first;
        port = int.tryParse(hp.length > 1 ? hp[1] : '443') ?? 443;
      }
    }
    if (port == 0) port = 443;
    return ProxyConfig(
      protocol: 'ss',
      name: name.isEmpty ? 'ss $host' : name,
      address: host,
      port: port,
      raw: link,
    );
  }
}

// ---------------- Storage ----------------
class ConfigStore {
  static const _key = 'nst_configs_v1';
  static Future<List<String>> loadRaw() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_key) ?? <String>[];
  }
  static Future<void> saveRaw(List<String> raws) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, raws);
  }
}

// ---------------- App ----------------
class NstTunnelApp extends StatelessWidget {
  const NstTunnelApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kBrand, brightness: Brightness.dark)
        .copyWith(primary: kBrand, surface: kSurface);
    return MaterialApp(
      title: 'NST Tunnel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: kBg),
      home: const HomeShell(),
    );
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raws = await ConfigStore.loadRaw();
    final list = <ProxyConfig>[];
    for (final r in raws) {
      final c = ConfigParser.parseOne(r);
      if (c != null) list.add(c);
    }
    setState(() {
      _configs = list;
      _selected = list.isNotEmpty ? list.first : null;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await ConfigStore.saveRaw(_configs.map((e) => e.raw).toList());
  }

  Future<void> _addConfigs(List<ProxyConfig> added) async {
    if (added.isEmpty) return;
    final existing = _configs.map((e) => e.raw).toSet();
    final fresh = added.where((c) => !existing.contains(c.raw)).toList();
    setState(() {
      _configs = [..._configs, ...fresh];
      _selected ??= _configs.isNotEmpty ? _configs.first : null;
    });
    await _persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${fresh.length} config(s)'), backgroundColor: kBrandDim),
      );
    }
  }

  Future<void> _remove(ProxyConfig c) async {
    setState(() {
      _configs.remove(c);
      if (_selected == c) _selected = _configs.isNotEmpty ? _configs.first : null;
    });
    await _persist();
  }

  void _select(ProxyConfig c) => setState(() { _selected = c; _index = 0; });

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBrand)));
    }
    final pages = [
      ConnectPage(server: _selected),
      ServersPage(configs: _configs, selected: _selected, onSelect: _select, onRemove: _remove, onAdd: _addConfigs),
      const SettingsPage(),
    ];
    return Scaffold(
      body: Row(children: [
        _SideRail(index: _index, onChange: (i) => setState(() => _index = i)),
        Container(width: 1, color: Colors.white.withOpacity(0.06)),
        Expanded(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Container(key: ValueKey(_index), child: pages[_index]),
        )),
      ]),
    );
  }
}

class _SideRail extends StatelessWidget {
  final int index; final ValueChanged<int> onChange;
  const _SideRail({required this.index, required this.onChange});
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.shield_outlined, Icons.shield, 'Connect'),
      (Icons.dns_outlined, Icons.dns, 'Servers'),
      (Icons.settings_outlined, Icons.settings, 'Settings'),
    ];
    return Container(
      width: 92, color: kSurface,
      child: Column(children: [
        const SizedBox(height: 28),
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kBrand, kBrandDim]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.bolt, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        const Text('NST', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 32),
        for (int i = 0; i < items.length; i++)
          _RailButton(icon: index == i ? items[i].$2 : items[i].$1, label: items[i].$3, active: index == i, onTap: () => onChange(i)),
        const Spacer(),
        const Padding(padding: EdgeInsets.only(bottom: 16), child: Text('v2.17.5', style: TextStyle(color: Colors.white38, fontSize: 11))),
      ]),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  const _RailButton({required this.icon, required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: active ? kBrand.withOpacity(0.16) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Icon(icon, color: active ? kBrand : Colors.white60, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: active ? kBrand : Colors.white60)),
          ]),
        ),
      ),
    );
  }
}

enum ConnState { off, connecting, on }

class ConnectPage extends StatefulWidget {
  final ProxyConfig? server;
  const ConnectPage({super.key, required this.server});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> with SingleTickerProviderStateMixin {
  ConnState _state = ConnState.off;
  Timer? _timer; int _seconds = 0;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  void _toggle() {
    if (widget.server == null) return;
    if (_state == ConnState.on) { _timer?.cancel(); setState(() { _state = ConnState.off; _seconds = 0; }); return; }
    setState(() => _state = ConnState.connecting);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _state = ConnState.on);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
    });
  }

  String get _elapsed {
    final h = (_seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((_seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() { _timer?.cancel(); _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final srv = widget.server;
    final on = _state == ConnState.on;
    final connecting = _state == ConnState.connecting;
    final statusText = srv == null ? 'No server — import a config' : on ? 'Protected' : connecting ? 'Connecting…' : 'Not connected';
    final statusColor = on ? kGood : connecting ? kBrand : Colors.white54;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dashboard', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Your secure tunnel at a glance', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        const Spacer(),
        Center(child: GestureDetector(
          onTap: _toggle,
          child: AnimatedBuilder(animation: _pulse, builder: (context, _) {
            final glow = on ? (0.25 + _pulse.value * 0.25) : 0.12;
            return Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: on ? [kGood, const Color(0xFF1E9E48)] : [kBrand, kBrandDim]),
                boxShadow: [BoxShadow(color: (on ? kGood : kBrand).withOpacity(glow), blurRadius: 50, spreadRadius: 8)],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(on ? Icons.lock : Icons.power_settings_new, color: Colors.white, size: 64),
                const SizedBox(height: 10),
                Text(on ? 'TAP TO STOP' : connecting ? 'WAIT' : 'TAP TO CONNECT', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 13)),
              ]),
            );
          }),
        )),
        const SizedBox(height: 28),
        Center(child: Column(children: [
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 20, fontWeight: FontWeight.w700)),
          if (on) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_elapsed, style: const TextStyle(color: Colors.white54, fontFeatures: [FontFeature.tabularFigures()]))),
        ])),
        const Spacer(),
        if (srv != null) Row(children: [
          Expanded(child: _StatCard(icon: Icons.public, label: 'Server', value: '${srv.flag}  ${srv.name}')),
          const SizedBox(width: 16),
          Expanded(child: _StatCard(icon: Icons.lan, label: 'Address', value: '${srv.address}:${srv.port}')),
          const SizedBox(width: 16),
          Expanded(child: _StatCard(icon: Icons.vpn_key, label: 'Protocol', value: srv.protocol.toUpperCase())),
        ]),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String label; final String value; final Color? valueColor;
  const _StatCard({required this.icon, required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: kBrand, size: 22),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: valueColor ?? Colors.white)),
        ]),
      ),
    );
  }
}

class ServersPage extends StatelessWidget {
  final List<ProxyConfig> configs;
  final ProxyConfig? selected;
  final ValueChanged<ProxyConfig> onSelect;
  final ValueChanged<ProxyConfig> onRemove;
  final Future<void> Function(List<ProxyConfig>) onAdd;
  const ServersPage({super.key, required this.configs, required this.selected, required this.onSelect, required this.onRemove, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kBrand,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add config', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showAddDialog(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Servers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Import vless:// vmess:// trojan:// ss:// links or a subscription URL', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 24),
          Expanded(
            child: configs.isEmpty
              ? _EmptyState(onAdd: () => _showAddDialog(context))
              : ListView.separated(
                  itemCount: configs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final s = configs[i];
                    final isSel = s == selected;
                    return Card(
                      color: kSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        leading: Text(s.flag, style: const TextStyle(fontSize: 26)),
                        title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${s.protocol.toUpperCase()} · ${s.address}:${s.port}', style: const TextStyle(color: Colors.white54)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isSel ? Icons.check_circle : Icons.circle_outlined, color: isSel ? kBrand : Colors.white24),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white38), onPressed: () => onRemove(s)),
                        ]),
                        onTap: () => onSelect(s),
                      ),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => _AddDialog(onAdd: onAdd));
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off, color: Colors.white24, size: 64),
        const SizedBox(height: 16),
        const Text('No configs yet', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Add a link or import a subscription to get started', style: TextStyle(color: Colors.white.withOpacity(0.4))),
        const SizedBox(height: 20),
        FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: kBrand), onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add config')),
      ]),
    );
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
  bool _busy = false;
  String? _error;

  Future<void> _importLinks() async {
    final text = _linkCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    final configs = ConfigParser.parseMany(ConfigParser.normalizeBody(text));
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
      final body = ConfigParser.normalizeBody(resp.body);
      final configs = ConfigParser.parseMany(body);
      setState(() => _busy = false);
      if (configs.isEmpty) { setState(() => _error = 'No configs in subscription'); return; }
      await widget.onAdd(configs);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _busy = false; _error = 'Failed: $e'; });
    }
  }

  @override
  void dispose() { _linkCtrl.dispose(); _subCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add config', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            const Text('Paste link(s)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _linkCtrl,
              maxLines: 4,
              style: const TextStyle(fontSize: 13),
              decoration: _dec('vless://...  vmess://...  trojan://...  ss://...'),
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kBrandDim),
              onPressed: _busy ? null : _importLinks,
              child: const Text('Import links'),
            )),
            const SizedBox(height: 12),
            Divider(color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 12),
            const Text('Or import a subscription URL', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _subCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: _dec('https://example.com/sub.txt'),
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kBrand),
              onPressed: _busy ? null : _importSubscription,
              icon: const Icon(Icons.cloud_download, size: 18),
              label: const Text('Fetch & import'),
            )),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator(color: kBrand))),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kBad))),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.white54)))),
          ]),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30),
    filled: true,
    fillColor: kBg,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );
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
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        Card(color: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: Column(children: [
          _toggle('Auto-connect on launch', 'Connect to last server automatically', _autoConnect, (v) => setState(() => _autoConnect = v)),
          _divider(),
          _toggle('Kill switch', 'Block traffic if the tunnel drops', _killSwitch, (v) => setState(() => _killSwitch = v)),
          _divider(),
          _toggle('Launch at startup', 'Open NST Tunnel when the system starts', _startup, (v) => setState(() => _startup = v)),
        ])),
        const SizedBox(height: 24),
        Card(color: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: const ListTile(
          leading: Icon(Icons.info_outline, color: kBrand),
          title: Text('About'),
          subtitle: Text('NST Tunnel desktop · v2.17.5 · Material 3'),
        )),
      ]),
    );
  }
  Widget _divider() => Divider(height: 1, color: Colors.white.withOpacity(0.06));
  Widget _toggle(String title, String sub, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      activeColor: kBrand,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: const TextStyle(color: Colors.white54)),
      value: value, onChanged: onChanged,
    );
  }
}
