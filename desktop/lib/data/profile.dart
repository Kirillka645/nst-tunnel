import 'package:flutter/foundation.dart';

/// All Xray-supported outbound protocols this client knows how to launch.
///
/// The values are the strings used in the Xray JSON config (`outbounds[].protocol`)
/// so we can map directly. Anything outside this list falls back to a custom JSON
/// import.
enum ProtocolType {
  vmess,
  vless,
  trojan,
  shadowsocks,
  socks,
  custom;

  String get displayName => switch (this) {
        vmess => 'VMess',
        vless => 'VLESS',
        trojan => 'Trojan',
        shadowsocks => 'Shadowsocks',
        socks => 'SOCKS',
        custom => 'Custom JSON',
      };
}

/// A connection profile — the data we need to build an Xray outbound config.
///
/// Designed to round-trip through SharedPreferences so users keep their servers
/// across launches; raw JSON storage avoids needing a heavyweight DB.
@immutable
class Profile {
  Profile({
    String? id,
    required this.protocol,
    required this.remarks,
    required this.address,
    required this.port,
    this.userId,
    this.password,
    this.method,
    this.alterId = 0,
    this.network = 'tcp',
    this.security,
    this.path,
    this.host,
    this.tls = false,
    this.sni,
    this.alpn,
    this.flow,
    this.publicKey,
    this.shortId,
    this.spiderX,
    this.fingerprint,
    this.rawJson,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final ProtocolType protocol;
  final String remarks;
  final String address;
  final int port;

  /// VMess UUID / VLESS UUID / Shadowsocks-2022 PSK source / SOCKS user.
  final String? userId;

  /// Trojan password / Shadowsocks password / SOCKS password.
  final String? password;

  /// Shadowsocks cipher.
  final String? method;

  /// VMess alterId (0 means AEAD).
  final int alterId;

  /// Transport: tcp, ws, grpc, h2, quic, kcp ...
  final String network;

  /// VMess security: auto, aes-128-gcm, chacha20-poly1305, none.
  final String? security;

  /// WebSocket / HTTP path; gRPC service name lives here too.
  final String? path;

  /// WebSocket / HTTP host header.
  final String? host;

  // TLS
  final bool tls;
  final String? sni;
  final String? alpn;
  final String? flow;

  // Reality
  final String? publicKey;
  final String? shortId;
  final String? spiderX;
  final String? fingerprint;

  /// For "custom" protocol — the user pastes raw Xray JSON.
  final Map<String, dynamic>? rawJson;

  Profile copyWith({
    String? remarks,
    String? address,
    int? port,
  }) {
    return Profile(
      id: id,
      protocol: protocol,
      remarks: remarks ?? this.remarks,
      address: address ?? this.address,
      port: port ?? this.port,
      userId: userId,
      password: password,
      method: method,
      alterId: alterId,
      network: network,
      security: security,
      path: path,
      host: host,
      tls: tls,
      sni: sni,
      alpn: alpn,
      flow: flow,
      publicKey: publicKey,
      shortId: shortId,
      spiderX: spiderX,
      fingerprint: fingerprint,
      rawJson: rawJson,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'protocol': protocol.name,
        'remarks': remarks,
        'address': address,
        'port': port,
        if (userId != null) 'userId': userId,
        if (password != null) 'password': password,
        if (method != null) 'method': method,
        'alterId': alterId,
        'network': network,
        if (security != null) 'security': security,
        if (path != null) 'path': path,
        if (host != null) 'host': host,
        'tls': tls,
        if (sni != null) 'sni': sni,
        if (alpn != null) 'alpn': alpn,
        if (flow != null) 'flow': flow,
        if (publicKey != null) 'publicKey': publicKey,
        if (shortId != null) 'shortId': shortId,
        if (spiderX != null) 'spiderX': spiderX,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (rawJson != null) 'rawJson': rawJson,
      };

  static Profile fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String?,
      protocol: ProtocolType.values.firstWhere(
        (p) => p.name == json['protocol'],
        orElse: () => ProtocolType.custom,
      ),
      remarks: json['remarks'] as String? ?? 'Unnamed',
      address: json['address'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      userId: json['userId'] as String?,
      password: json['password'] as String?,
      method: json['method'] as String?,
      alterId: (json['alterId'] as num?)?.toInt() ?? 0,
      network: json['network'] as String? ?? 'tcp',
      security: json['security'] as String?,
      path: json['path'] as String?,
      host: json['host'] as String?,
      tls: json['tls'] as bool? ?? false,
      sni: json['sni'] as String?,
      alpn: json['alpn'] as String?,
      flow: json['flow'] as String?,
      publicKey: json['publicKey'] as String?,
      shortId: json['shortId'] as String?,
      spiderX: json['spiderX'] as String?,
      fingerprint: json['fingerprint'] as String?,
      rawJson: (json['rawJson'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
