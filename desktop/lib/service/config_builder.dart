import '../data/profile.dart';

/// Generates an Xray-core compatible JSON config from a [Profile].
///
/// We always emit:
///   * an inbound `socks` listener on `127.0.0.1:[socksPort]` (default 10808),
///   * an inbound `http` listener on `127.0.0.1:[httpPort]` (default 10809),
///   * a single matching outbound for the profile,
///   * a `freedom` outbound named `direct` and a `blackhole` named `block`,
///   * routing rules: bypass private IPs / LAN; block bittorrent.
///
/// This mirrors the Android app's defaults so the same QR-imported profile
/// works on both platforms with no extra config.
class XrayConfigBuilder {
  XrayConfigBuilder._();

  static Map<String, dynamic> build(
    Profile profile, {
    int socksPort = 10808,
    int httpPort = 10809,
    bool sniffing = true,
  }) {
    if (profile.protocol == ProtocolType.custom && profile.rawJson != null) {
      // User pasted full Xray JSON — trust it but still add the local inbounds
      // if they're absent so the desktop UI has a port to point at.
      return _wrapCustom(profile.rawJson!, socksPort, httpPort);
    }

    return {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'tag': 'socks',
          'port': socksPort,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          if (sniffing)
            'sniffing': {
              'enabled': true,
              'destOverride': ['http', 'tls'],
            },
        },
        {
          'tag': 'http',
          'port': httpPort,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': {},
          if (sniffing)
            'sniffing': {
              'enabled': true,
              'destOverride': ['http', 'tls'],
            },
        },
      ],
      'outbounds': [
        _outbound(profile),
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {},
        },
        {
          'tag': 'block',
          'protocol': 'blackhole',
          'settings': {'response': {'type': 'http'}},
        },
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'type': 'field',
            'outboundTag': 'direct',
            'ip': ['geoip:private'],
          },
          {
            'type': 'field',
            'outboundTag': 'block',
            'protocol': ['bittorrent'],
          },
        ],
      },
    };
  }

  static Map<String, dynamic> _wrapCustom(
    Map<String, dynamic> raw,
    int socksPort,
    int httpPort,
  ) {
    final cfg = Map<String, dynamic>.of(raw);
    cfg.putIfAbsent('inbounds', () => []);
    final inbounds = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
    if (!inbounds.any((i) => i['protocol'] == 'socks' && i['listen'] == '127.0.0.1')) {
      inbounds.add({
        'tag': 'socks',
        'port': socksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
      });
    }
    if (!inbounds.any((i) => i['protocol'] == 'http' && i['listen'] == '127.0.0.1')) {
      inbounds.add({
        'tag': 'http',
        'port': httpPort,
        'listen': '127.0.0.1',
        'protocol': 'http',
      });
    }
    return cfg;
  }

  static Map<String, dynamic> _outbound(Profile p) {
    final stream = _streamSettings(p);
    final settings = switch (p.protocol) {
      ProtocolType.vmess => {
          'vnext': [
            {
              'address': p.address,
              'port': p.port,
              'users': [
                {
                  'id': p.userId,
                  'alterId': p.alterId,
                  'security': p.security ?? 'auto',
                  'level': 8,
                },
              ],
            },
          ],
        },
      ProtocolType.vless => {
          'vnext': [
            {
              'address': p.address,
              'port': p.port,
              'users': [
                {
                  'id': p.userId,
                  'encryption': p.security ?? 'none',
                  if (p.flow != null && p.flow!.isNotEmpty) 'flow': p.flow,
                  'level': 8,
                },
              ],
            },
          ],
        },
      ProtocolType.trojan => {
          'servers': [
            {
              'address': p.address,
              'port': p.port,
              'password': p.password ?? '',
              'level': 8,
            },
          ],
        },
      ProtocolType.shadowsocks => {
          'servers': [
            {
              'address': p.address,
              'port': p.port,
              'method': p.method ?? 'aes-256-gcm',
              'password': p.password ?? '',
              'level': 8,
            },
          ],
        },
      ProtocolType.socks => {
          'servers': [
            {
              'address': p.address,
              'port': p.port,
              if (p.userId != null && p.password != null)
                'users': [
                  {'user': p.userId, 'pass': p.password, 'level': 8},
                ],
            },
          ],
        },
      ProtocolType.custom => <String, dynamic>{}, // unreachable; handled above
    };

    return {
      'tag': 'proxy',
      'protocol': p.protocol.name,
      'settings': settings,
      if (stream != null) 'streamSettings': stream,
    };
  }

  static Map<String, dynamic>? _streamSettings(Profile p) {
    final settings = <String, dynamic>{
      'network': p.network,
      'security': p.tls ? 'tls' : 'none',
    };

    if (p.tls) {
      settings['tlsSettings'] = {
        if (p.sni != null && p.sni!.isNotEmpty) 'serverName': p.sni,
        if (p.alpn != null && p.alpn!.isNotEmpty)
          'alpn': p.alpn!.split(',').map((e) => e.trim()).toList(),
        if (p.fingerprint != null) 'fingerprint': p.fingerprint,
        'allowInsecure': false,
      };
    }
    if (p.publicKey != null && p.publicKey!.isNotEmpty) {
      settings['security'] = 'reality';
      settings['realitySettings'] = {
        'publicKey': p.publicKey,
        if (p.shortId != null) 'shortId': p.shortId,
        if (p.spiderX != null) 'spiderX': p.spiderX,
        if (p.fingerprint != null) 'fingerprint': p.fingerprint,
        if (p.sni != null) 'serverName': p.sni,
      };
    }

    switch (p.network) {
      case 'ws':
        settings['wsSettings'] = {
          if (p.path != null) 'path': p.path,
          if (p.host != null) 'headers': {'Host': p.host},
        };
        break;
      case 'grpc':
        settings['grpcSettings'] = {
          if (p.path != null) 'serviceName': p.path,
        };
        break;
      case 'h2':
        settings['httpSettings'] = {
          if (p.path != null) 'path': p.path,
          if (p.host != null) 'host': p.host!.split(',').map((e) => e.trim()).toList(),
        };
        break;
      case 'tcp':
      default:
        // Plain TCP — no extra settings unless you're doing HTTP obfuscation,
        // which the share-URI formats we accept don't carry.
        break;
    }

    return settings;
  }
}
