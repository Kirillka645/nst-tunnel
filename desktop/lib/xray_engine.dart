import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local proxy ports exposed by the embedded Xray instance.
const int kSocksPort = 10808;
const int kHttpPort = 10809;

/// Where we expect the bundled xray binary to live relative to the executable.
String _xrayBinaryPath() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isWindows) {
    // Bundled next to the exe (Flutter copies data/ alongside). Try a few spots.
    final candidates = [
      '$exeDir\\xray.exe',
      '$exeDir\\data\\flutter_assets\\assets\\bin\\xray.exe',
    ];
    for (final c in candidates) { if (File(c).existsSync()) return c; }
    return candidates.first;
  } else {
    final candidates = [
      '$exeDir/xray',
      '$exeDir/../Resources/xray',
      '$exeDir/../Frameworks/xray',
    ];
    for (final c in candidates) { if (File(c).existsSync()) return c; }
    return candidates.first;
  }
}

/// Parsed proxy → Xray outbound JSON converter.
class XrayConfigBuilder {
  static Map<String, dynamic> build(String rawLink) {
    final outbound = _outbound(rawLink);
    return {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'tag': 'socks',
          'port': kSocksPort,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'udp': true, 'auth': 'noauth'},
          'sniffing': {'enabled': true, 'destOverride': ['http', 'tls']},
        },
        {
          'tag': 'http',
          'port': kHttpPort,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': {},
        },
      ],
      'outbounds': [
        outbound,
        {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
        {'tag': 'block', 'protocol': 'blackhole', 'settings': {}},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'},
        ],
      },
    };
  }

  static Map<String, dynamic> _outbound(String link) {
    if (link.startsWith('vless://')) return _vless(link);
    if (link.startsWith('vmess://')) return _vmess(link);
    if (link.startsWith('trojan://')) return _trojan(link);
    if (link.startsWith('ss://')) return _ss(link);
    throw FormatException('Unsupported link: $link');
  }

  static Map<String, dynamic> _stream(Map<String, String> q) {
    final net = (q['type'] ?? 'tcp').toLowerCase();
    final sec = (q['security'] ?? 'none').toLowerCase();
    final stream = <String, dynamic>{'network': net, 'security': sec};

    if (sec == 'tls') {
      stream['tlsSettings'] = {
        if (q['sni'] != null) 'serverName': q['sni'],
        if (q['fp'] != null) 'fingerprint': q['fp'],
        if (q['alpn'] != null) 'alpn': q['alpn']!.split(','),
        'allowInsecure': q['allowInsecure'] == '1',
      };
    } else if (sec == 'reality') {
      stream['realitySettings'] = {
        if (q['sni'] != null) 'serverName': q['sni'],
        if (q['fp'] != null) 'fingerprint': q['fp'],
        if (q['pbk'] != null) 'publicKey': q['pbk'],
        if (q['sid'] != null) 'shortId': q['sid'],
        if (q['spx'] != null) 'spiderX': q['spx'],
      };
    }

    if (net == 'ws') {
      stream['wsSettings'] = {
        'path': q['path'] ?? '/',
        if (q['host'] != null) 'headers': {'Host': q['host']},
      };
    } else if (net == 'grpc') {
      stream['grpcSettings'] = {'serviceName': q['serviceName'] ?? q['path'] ?? ''};
    } else if (net == 'tcp' && (q['headerType'] == 'http')) {
      stream['tcpSettings'] = {
        'header': {
          'type': 'http',
          if (q['host'] != null) 'request': {'headers': {'Host': [q['host']]}},
        }
      };
    }
    return stream;
  }

  static Map<String, dynamic> _vless(String link) {
    final uri = Uri.parse(link);
    final q = uri.queryParameters;
    return {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': uri.host,
            'port': uri.port == 0 ? 443 : uri.port,
            'users': [
              {
                'id': uri.userInfo,
                'encryption': q['encryption'] ?? 'none',
                if (q['flow'] != null && q['flow']!.isNotEmpty) 'flow': q['flow'],
              }
            ],
          }
        ],
      },
      'streamSettings': _stream(q),
    };
  }

  static Map<String, dynamic> _vmess(String link) {
    final j = jsonDecode(utf8.decode(base64.decode(base64.normalize(link.substring(8)))));
    final q = <String, String>{
      'type': (j['net'] ?? 'tcp').toString(),
      'security': (j['tls'] ?? 'none').toString().isEmpty ? 'none' : (j['tls'] ?? 'none').toString(),
      if (j['sni'] != null) 'sni': j['sni'].toString(),
      if (j['host'] != null) 'host': j['host'].toString(),
      if (j['path'] != null) 'path': j['path'].toString(),
      if (j['fp'] != null) 'fp': j['fp'].toString(),
    };
    return {
      'tag': 'proxy',
      'protocol': 'vmess',
      'settings': {
        'vnext': [
          {
            'address': (j['add'] ?? '').toString(),
            'port': int.tryParse((j['port'] ?? '443').toString()) ?? 443,
            'users': [
              {
                'id': (j['id'] ?? '').toString(),
                'alterId': int.tryParse((j['aid'] ?? '0').toString()) ?? 0,
                'security': (j['scy'] ?? 'auto').toString(),
              }
            ],
          }
        ],
      },
      'streamSettings': _stream(q),
    };
  }

  static Map<String, dynamic> _trojan(String link) {
    final uri = Uri.parse(link);
    final q = uri.queryParameters;
    final st = _stream({...q, 'security': q['security'] ?? 'tls'});
    return {
      'tag': 'proxy',
      'protocol': 'trojan',
      'settings': {
        'servers': [
          {'address': uri.host, 'port': uri.port == 0 ? 443 : uri.port, 'password': uri.userInfo}
        ],
      },
      'streamSettings': st,
    };
  }

  static Map<String, dynamic> _ss(String link) {
    final uri = Uri.parse(link);
    String method = '', password = '', host = uri.host;
    int port = uri.port == 0 ? 443 : uri.port;
    if (uri.userInfo.contains(':')) {
      final parts = uri.userInfo.split(':');
      method = parts[0]; password = parts.sublist(1).join(':');
    } else {
      final dec = utf8.decode(base64.decode(base64.normalize(uri.userInfo)), allowMalformed: true);
      final c = dec.split(':'); method = c.first; password = c.sublist(1).join(':');
    }
    return {
      'tag': 'proxy',
      'protocol': 'shadowsocks',
      'settings': {
        'servers': [
          {'address': host, 'port': port, 'method': method, 'password': password}
        ],
      },
    };
  }
}

/// Manages the xray subprocess + system proxy toggling.
class XrayEngine {
  static final XrayEngine instance = XrayEngine._();
  XrayEngine._();

  Process? _proc;
  bool get running => _proc != null;

  Future<File> _writeConfig(String rawLink) async {
    final dir = Directory.systemTemp.createTempSync('nst_xray');
    final f = File('${dir.path}${Platform.pathSeparator}config.json');
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(XrayConfigBuilder.build(rawLink)));
    return f;
  }

  Future<void> start(String rawLink) async {
    await stop();
    final cfg = await _writeConfig(rawLink);
    final bin = _xrayBinaryPath();
    if (!File(bin).existsSync()) {
      throw Exception('xray binary not found at $bin');
    }
    _proc = await Process.start(bin, ['run', '-c', cfg.path]);
    _proc!.stderr.transform(utf8.decoder).listen((_) {});
    _proc!.stdout.transform(utf8.decoder).listen((_) {});
    await Future.delayed(const Duration(milliseconds: 800));
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
