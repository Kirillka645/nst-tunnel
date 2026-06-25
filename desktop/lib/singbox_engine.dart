import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local proxy ports exposed by the embedded sing-box instance.
const int kSocksPort = 10808;
const int kHttpPort = 10809;

/// Builds a sing-box config from a single share link.
/// Supports: vless, vmess, trojan, shadowsocks, hysteria2/hy2, hysteria, tuic.
class SingBoxConfig {
  static Map<String, dynamic> build(String rawLink) {
    final outbound = _outbound(rawLink.trim());
    return {
      'log': {'level': 'warn'},
      'inbounds': [
        {'type': 'socks', 'tag': 'socks-in', 'listen': '127.0.0.1', 'listen_port': kSocksPort, 'sniff': true},
        {'type': 'mixed', 'tag': 'mixed-in', 'listen': '127.0.0.1', 'listen_port': kHttpPort, 'sniff': true},
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
        {'type': 'dns', 'tag': 'dns-out'},
      ],
      'route': {
        'rules': [
          {'protocol': 'dns', 'outbound': 'dns-out'},
          {'ip_is_private': true, 'outbound': 'direct'},
        ],
        'final': 'proxy',
      },
    };
  }

  static Map<String, dynamic> _outbound(String link) {
    if (link.startsWith('vmess://')) return _vmess(link);
    if (link.startsWith('vless://')) return _vless(link);
    if (link.startsWith('trojan://')) return _trojan(link);
    if (link.startsWith('ss://')) return _ss(link);
    if (link.startsWith('hysteria2://') || link.startsWith('hy2://')) return _hysteria2(link);
    if (link.startsWith('hysteria://')) return _hysteria(link);
    if (link.startsWith('tuic://')) return _tuic(link);
    throw Exception('Unsupported link');
  }

  static int _port(Uri u, [int def = 443]) => u.hasPort ? u.port : def;
  static Map<String, String> _q(Uri u) => u.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));

  static List<String>? _alpn(Map<String, String> q) {
    final a = q['alpn'];
    if (a == null || a.isEmpty) return null;
    return a.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static bool _insecure(Map<String, String> q) {
    final v = (q['allowinsecure'] ?? q['insecure'] ?? q['allow_insecure'] ?? '').toLowerCase();
    return v == '1' || v == 'true';
  }

  static Map<String, dynamic>? _tls(Uri u, Map<String, String> q, {bool force = false}) {
    final sec = (q['security'] ?? '').toLowerCase();
    final enabled = force || sec == 'tls' || sec == 'reality' || sec == 'xtls';
    if (!enabled) return null;
    final sni = q['sni'] ?? q['peer'] ?? q['host'] ?? u.host;
    final tls = <String, dynamic>{'enabled': true, 'server_name': sni, 'insecure': _insecure(q)};
    final alpn = _alpn(q);
    if (alpn != null) tls['alpn'] = alpn;
    final fp = q['fp'];
    if (fp != null && fp.isNotEmpty) tls['utls'] = {'enabled': true, 'fingerprint': fp};
    if (sec == 'reality') {
      final reality = <String, dynamic>{'enabled': true};
      if (q['pbk'] != null) reality['public_key'] = q['pbk'];
      if (q['sid'] != null) reality['short_id'] = q['sid'];
      tls['reality'] = reality;
      tls['utls'] = {'enabled': true, 'fingerprint': (fp == null || fp.isEmpty) ? 'chrome' : fp};
    }
    return tls;
  }

  static Map<String, dynamic>? _transport(Map<String, String> q) {
    final type = (q['type'] ?? '').toLowerCase();
    if (type == 'ws') {
      final t = <String, dynamic>{'type': 'ws'};
      if (q['path'] != null) t['path'] = q['path'];
      final host = q['host'];
      if (host != null && host.isNotEmpty) t['headers'] = {'Host': host};
      return t;
    }
    if (type == 'grpc') return {'type': 'grpc', 'service_name': q['servicename'] ?? ''};
    if (type == 'http' || type == 'h2') {
      final t = <String, dynamic>{'type': 'http'};
      if (q['path'] != null) t['path'] = q['path'];
      final host = q['host'];
      if (host != null && host.isNotEmpty) t['host'] = [host];
      return t;
    }
    return null;
  }

  static Map<String, dynamic> _vless(String link) {
    final u = Uri.parse(link);
    final q = _q(u);
    final o = <String, dynamic>{'type': 'vless', 'tag': 'proxy', 'server': u.host, 'server_port': _port(u), 'uuid': u.userInfo};
    final flow = q['flow'];
    if (flow != null && flow.isNotEmpty) o['flow'] = flow;
    final tls = _tls(u, q);
    if (tls != null) o['tls'] = tls;
    final tr = _transport(q);
    if (tr != null) o['transport'] = tr;
    return o;
  }

  static Map<String, dynamic> _vmess(String link) {
    var b = link.substring('vmess://'.length).trim();
    b = b.replaceAll('-', '+').replaceAll('_', '/');
    while (b.length % 4 != 0) { b += '='; }
    final j = jsonDecode(utf8.decode(base64.decode(b))) as Map<String, dynamic>;
    String s(dynamic v) => v?.toString() ?? '';
    final o = <String, dynamic>{
      'type': 'vmess', 'tag': 'proxy', 'server': s(j['add']),
      'server_port': int.tryParse(s(j['port'])) ?? 443, 'uuid': s(j['id']),
      'alter_id': int.tryParse(s(j['aid'])) ?? 0,
      'security': s(j['scy']).isEmpty ? 'auto' : s(j['scy']),
    };
    final net = s(j['net']).toLowerCase();
    if (s(j['tls']).toLowerCase() == 'tls') {
      o['tls'] = {'enabled': true, 'server_name': s(j['sni']).isNotEmpty ? s(j['sni']) : (s(j['host']).isNotEmpty ? s(j['host']) : s(j['add'])), 'insecure': false};
    }
    if (net == 'ws') {
      final t = <String, dynamic>{'type': 'ws'};
      if (s(j['path']).isNotEmpty) t['path'] = s(j['path']);
      if (s(j['host']).isNotEmpty) t['headers'] = {'Host': s(j['host'])};
      o['transport'] = t;
    } else if (net == 'grpc') {
      o['transport'] = {'type': 'grpc', 'service_name': s(j['path'])};
    } else if (net == 'h2' || net == 'http') {
      final t = <String, dynamic>{'type': 'http'};
      if (s(j['path']).isNotEmpty) t['path'] = s(j['path']);
      if (s(j['host']).isNotEmpty) t['host'] = [s(j['host'])];
      o['transport'] = t;
    }
    return o;
  }

  static Map<String, dynamic> _trojan(String link) {
    final u = Uri.parse(link);
    final q = _q(u);
    final o = <String, dynamic>{'type': 'trojan', 'tag': 'proxy', 'server': u.host, 'server_port': _port(u), 'password': u.userInfo};
    final tls = _tls(u, q, force: true);
    if (tls != null) o['tls'] = tls;
    final tr = _transport(q);
    if (tr != null) o['transport'] = tr;
    return o;
  }

  static Map<String, dynamic> _ss(String link) {
    var body = link.substring('ss://'.length);
    final hashIdx = body.indexOf('#');
    if (hashIdx != -1) body = body.substring(0, hashIdx);
    String method = '', password = '', host = '', portStr = '443';
    final at = body.indexOf('@');
    if (at != -1) {
      var userPart = body.substring(0, at);
      var hostPart = body.substring(at + 1);
      final qIdx = hostPart.indexOf('?');
      if (qIdx != -1) hostPart = hostPart.substring(0, qIdx);
      final hp = hostPart.split(':');
      host = hp.first;
      if (hp.length > 1) portStr = hp[1];
      try {
        var pad = userPart.replaceAll('-', '+').replaceAll('_', '/');
        while (pad.length % 4 != 0) { pad += '='; }
        final dec = utf8.decode(base64.decode(pad));
        if (dec.contains(':')) userPart = dec;
      } catch (_) {}
      final mp = userPart.split(':');
      method = mp.first;
      password = mp.length > 1 ? mp.sublist(1).join(':') : '';
    } else {
      try {
        var pad = body.replaceAll('-', '+').replaceAll('_', '/');
        while (pad.length % 4 != 0) { pad += '='; }
        final dec = utf8.decode(base64.decode(pad));
        final at2 = dec.lastIndexOf('@');
        final up = dec.substring(0, at2).split(':');
        method = up.first; password = up.length > 1 ? up.sublist(1).join(':') : '';
        final hp = dec.substring(at2 + 1).split(':');
        host = hp.first; if (hp.length > 1) portStr = hp[1];
      } catch (_) {}
    }
    return {'type': 'shadowsocks', 'tag': 'proxy', 'server': host, 'server_port': int.tryParse(portStr) ?? 443, 'method': method, 'password': password};
  }

  static Map<String, dynamic> _hysteria2(String link) {
    final u = Uri.parse(link);
    final q = _q(u);
    final o = <String, dynamic>{
      'type': 'hysteria2', 'tag': 'proxy', 'server': u.host, 'server_port': _port(u), 'password': u.userInfo,
      'tls': {'enabled': true, 'server_name': q['sni'] ?? u.host, 'insecure': _insecure(q)},
    };
    final alpn = _alpn(q);
    if (alpn != null) (o['tls'] as Map)['alpn'] = alpn;
    final obfs = q['obfs'];
    if (obfs != null && obfs.isNotEmpty) o['obfs'] = {'type': obfs, 'password': q['obfs-password'] ?? q['obfspassword'] ?? ''};
    return o;
  }

  static Map<String, dynamic> _hysteria(String link) {
    final u = Uri.parse(link);
    final q = _q(u);
    final o = <String, dynamic>{
      'type': 'hysteria', 'tag': 'proxy', 'server': u.host, 'server_port': _port(u),
      'tls': {'enabled': true, 'server_name': q['peer'] ?? q['sni'] ?? u.host, 'insecure': _insecure(q)},
    };
    final auth = q['auth'] ?? u.userInfo;
    if (auth.isNotEmpty) o['auth_str'] = auth;
    final up = q['upmbps'] ?? q['up'];
    final down = q['downmbps'] ?? q['down'];
    if (up != null) o['up_mbps'] = int.tryParse(up.replaceAll(RegExp(r'[^0-9]'), '')) ?? 50;
    if (down != null) o['down_mbps'] = int.tryParse(down.replaceAll(RegExp(r'[^0-9]'), '')) ?? 100;
    final alpn = _alpn(q);
    if (alpn != null) (o['tls'] as Map)['alpn'] = alpn;
    return o;
  }

  static Map<String, dynamic> _tuic(String link) {
    final u = Uri.parse(link);
    final q = _q(u);
    final ui = u.userInfo;
    String uuid = ui, password = '';
    if (ui.contains(':')) { final p = ui.split(':'); uuid = p.first; password = p.sublist(1).join(':'); }
    final o = <String, dynamic>{
      'type': 'tuic', 'tag': 'proxy', 'server': u.host, 'server_port': _port(u), 'uuid': uuid, 'password': password,
      'congestion_control': q['congestion_control'] ?? q['congestion'] ?? 'bbr',
      'tls': {'enabled': true, 'server_name': q['sni'] ?? u.host, 'insecure': _insecure(q), 'alpn': _alpn(q) ?? ['h3']},
    };
    final udp = q['udp_relay_mode'] ?? q['udprelaymode'];
    if (udp != null) o['udp_relay_mode'] = udp;
    return o;
  }
}

/// Universal engine backed by sing-box (handles every supported protocol).
class XrayEngine {
  static final XrayEngine instance = XrayEngine._();
  XrayEngine._();

  Process? _proc;
  bool get running => _proc != null;

  Future<File> _writeConfig(String rawLink) async {
    final dir = Directory.systemTemp.createTempSync('nst_singbox');
    final f = File('${dir.path}${Platform.pathSeparator}config.json');
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(SingBoxConfig.build(rawLink)));
    return f;
  }

  String _binaryPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final name = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
    final candidates = <String>[
      '$exeDir$sep$name',
      '$exeDir${sep}data${sep}flutter_assets${sep}assets$sep$name',
      '$exeDir$sep..${sep}Resources$sep$name',
    ];
    for (final c in candidates) { if (File(c).existsSync()) return c; }
    return name;
  }

  Future<void> start(String rawLink) async {
    await stop();
    final cfg = await _writeConfig(rawLink);
    final bin = _binaryPath();
    if (!Platform.isWindows) { try { await Process.run('chmod', ['+x', bin]); } catch (_) {} }
    _proc = await Process.start(bin, ['run', '-c', cfg.path]);
    await Future.delayed(const Duration(milliseconds: 900));
    await _setSystemProxy(true);
  }

  Future<void> stop() async {
    if (_proc != null) {
      await _setSystemProxy(false);
      _proc!.kill();
      _proc = null;
    }
  }

  Future<void> _setSystemProxy(bool on) async {
    try {
      if (Platform.isWindows) {
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        if (on) {
          await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
          await Process.run('reg', ['add', key, '/v', 'ProxyServer', '/d', '127.0.0.1:$kHttpPort', '/f']);
        } else {
          await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
        }
      } else if (Platform.isMacOS) {
        const svc = 'Wi-Fi';
        if (on) {
          await Process.run('networksetup', ['-setwebproxy', svc, '127.0.0.1', '$kHttpPort']);
          await Process.run('networksetup', ['-setsecurewebproxy', svc, '127.0.0.1', '$kHttpPort']);
          await Process.run('networksetup', ['-setsocksfirewallproxy', svc, '127.0.0.1', '$kSocksPort']);
        } else {
          await Process.run('networksetup', ['-setwebproxystate', svc, 'off']);
          await Process.run('networksetup', ['-setsecurewebproxystate', svc, 'off']);
          await Process.run('networksetup', ['-setsocksfirewallproxystate', svc, 'off']);
        }
      }
    } catch (_) {}
  }
}
