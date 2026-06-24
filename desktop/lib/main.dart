import 'dart:async';
import 'package:flutter/material.dart';

void main() => runApp(const NstTunnelApp());

const kBrand = Color(0xFFF97910);
const kBrandDim = Color(0xFFB85A0B);
const kBg = Color(0xFF131114);
const kSurface = Color(0xFF1C1A1E);
const kGood = Color(0xFF34C759);
const kBad = Color(0xFFE5484D);

class NstTunnelApp extends StatelessWidget {
  const NstTunnelApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kBrand, brightness: Brightness.dark,
    ).copyWith(primary: kBrand, surface: kSurface);
    return MaterialApp(
      title: 'NST Tunnel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBg,
      ),
      home: const HomeShell(),
    );
  }
}

class Server {
  final String name; final String country; final String flag; final int ping;
  const Server(this.name, this.country, this.flag, this.ping);
}

const kServers = <Server>[
  Server('Amsterdam #1', 'Netherlands', '🇳🇱', 24),
  Server('Frankfurt #3', 'Germany', '🇩🇪', 31),
  Server('Stockholm #2', 'Sweden', '🇸🇪', 38),
  Server('Tokyo #5', 'Japan', '🇯🇵', 112),
  Server('Singapore #1', 'Singapore', '🇸🇬', 96),
  Server('New York #4', 'United States', '🇺🇸', 74),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  Server _selected = kServers.first;
  void _selectServer(Server s) => setState(() { _selected = s; _index = 0; });

  @override
  Widget build(BuildContext context) {
    final pages = [
      ConnectPage(server: _selected),
      ServersPage(selected: _selected, onSelect: _selectServer),
      const SettingsPage(),
    ];
    return Scaffold(
      body: Row(children: [
        _SideRail(index: _index, onChange: (i) => setState(() => _index = i)),
        Container(width: 1, color: Colors.white.withOpacity(0.06)),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Container(key: ValueKey(_index), child: pages[_index]),
          ),
        ),
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
          _RailButton(
            icon: index == i ? items[i].$2 : items[i].$1,
            label: items[i].$3,
            active: index == i,
            onTap: () => onChange(i),
          ),
        const Spacer(),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('v2.17.4', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
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
          decoration: BoxDecoration(
            color: active ? kBrand.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
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
  final Server server;
  const ConnectPage({super.key, required this.server});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> with SingleTickerProviderStateMixin {
  ConnState _state = ConnState.off;
  Timer? _timer; int _seconds = 0;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  void _toggle() {
    if (_state == ConnState.on) {
      _timer?.cancel();
      setState(() { _state = ConnState.off; _seconds = 0; });
      return;
    }
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
    final on = _state == ConnState.on;
    final connecting = _state == ConnState.connecting;
    final statusText = on ? 'Protected' : connecting ? 'Connecting…' : 'Not connected';
    final statusColor = on ? kGood : connecting ? kBrand : Colors.white54;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dashboard', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Your secure tunnel at a glance', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        const Spacer(),
        Center(
          child: GestureDetector(
            onTap: _toggle,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final glow = on ? (0.25 + _pulse.value * 0.25) : 0.12;
                return Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: on ? [kGood, const Color(0xFF1E9E48)] : [kBrand, kBrandDim],
                    ),
                    boxShadow: [
                      BoxShadow(color: (on ? kGood : kBrand).withOpacity(glow), blurRadius: 50, spreadRadius: 8),
                    ],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(on ? Icons.lock : Icons.power_settings_new, color: Colors.white, size: 64),
                    const SizedBox(height: 10),
                    Text(
                      on ? 'TAP TO STOP' : connecting ? 'WAIT' : 'TAP TO CONNECT',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 13),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 28),
        Center(child: Column(children: [
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 20, fontWeight: FontWeight.w700)),
          if (on) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_elapsed, style: const TextStyle(color: Colors.white54, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ])),
        const Spacer(),
        Row(children: [
          Expanded(child: _StatCard(icon: Icons.public, label: 'Server', value: '${widget.server.flag}  ${widget.server.name}')),
          const SizedBox(width: 16),
          Expanded(child: _StatCard(icon: Icons.speed, label: 'Ping', value: '${widget.server.ping} ms', valueColor: widget.server.ping < 80 ? kGood : kBad)),
          const SizedBox(width: 16),
          Expanded(child: _StatCard(icon: Icons.swap_vert, label: 'Traffic', value: on ? '128 MB' : '—')),
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
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: valueColor ?? Colors.white)),
        ]),
      ),
    );
  }
}

class ServersPage extends StatelessWidget {
  final Server selected; final ValueChanged<Server> onSelect;
  const ServersPage({super.key, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Servers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Pick the fastest location', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            itemCount: kServers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final s = kServers[i];
              final isSel = s.name == selected.name;
              final fast = s.ping < 80;
              return Card(
      color: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  leading: Text(s.flag, style: const TextStyle(fontSize: 28)),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s.country, style: const TextStyle(color: Colors.white54)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (fast ? kGood : kBad).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${s.ping} ms', style: TextStyle(color: fast ? kGood : kBad, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    Icon(isSel ? Icons.check_circle : Icons.circle_outlined, color: isSel ? kBrand : Colors.white24),
                  ]),
                  onTap: () => onSelect(s),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
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
        Card(child: Column(children: [
          _toggle('Auto-connect on launch', 'Connect to last server automatically', _autoConnect, (v) => setState(() => _autoConnect = v)),
          _divider(),
          _toggle('Kill switch', 'Block traffic if the tunnel drops', _killSwitch, (v) => setState(() => _killSwitch = v)),
          _divider(),
          _toggle('Launch at startup', 'Open NST Tunnel when the system starts', _startup, (v) => setState(() => _startup = v)),
        ])),
        const SizedBox(height: 24),
        Card(child: ListTile(
          leading: const Icon(Icons.info_outline, color: kBrand),
          title: const Text('About'),
          subtitle: const Text('NST Tunnel desktop · v2.17.4 · Material 3'),
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
