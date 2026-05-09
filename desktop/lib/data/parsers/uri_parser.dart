import 'dart:convert';

import '../profile.dart';

/// Parses share-link URIs into [Profile] objects.
///
/// Supports the four most common formats used by Xray clients in the wild:
///   * `vmess://` (base64 JSON, JSON-as-text payload)
///   * `vless://` (URI form: vless://uuid@host:port?params#remarks)
///   * `trojan://` (URI form: trojan://password@host:port?params#remarks)
///   * `ss://` (Shadowsocks SIP002: ss://base64(method:password)@host:port#remarks)
///
/// Failures throw a [FormatException] with a human-readable reason — UI
/// surfaces them via SnackBar.
class ShareUriParser {
  ShareUriParser._();

  static Profile parse(String uri) {
    final trimmed = uri.trim();
    if (trimmed.startsWith('vmess://')) return _parseVmess(trimmed);
    if (trimmed.startsWith('vless://')) return _parseVlessLike(trimmed, ProtocolType.vless);
    if (trimmed.startsWith('trojan://')) return _parseVlessLike(trimmed, ProtocolType.trojan);
    if (trimmed.startsWith('ss://')) return _parseShadowsocks(trimmed);
    throw const FormatException('Unsupported scheme. Expected vmess://, vless://, trojan:// or ss://.');
  }

  /// Detects whether [text] contains a share URI we know how to parse.
  static bool isShareUri(String text) {
    final t = text.trim();
    return t.startsWith('vmess://') ||
        t.startsWith('vless://') ||
        t.startsWith('trojan://') ||
        t.startsWith('ss://');
  }

  // -------------------------------------------------------------------------
  // VMess (legacy "JSON-in-base64" form, defined by v2rayN years ago).
  // -------------------------------------------------------------------------
  static Profile _parseVmess(String uri) {
    final body = uri.substring('vmess://'.length);
    final decoded = _b64Decode(body);
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('vmess:// payload is not valid JSON');
    }
    return Profile(
      protocol: ProtocolType.vmess,
      remarks: (j['ps'] ?? j['remarks'] ?? 'VMess') as String,
      address: (j['add'] ?? j['address'] ?? '') as String,
      port: int.tryParse('${j['port']}') ?? 0,
      userId: j['id'] as String?,
      alterId: int.tryParse('${j['aid'] ?? 0}') ?? 0,
      network: (j['net'] as String?) ?? 'tcp',
      security: j['scy'] as String? ?? j['security'] as String?,
      path: j['path'] as String?,
      host: j['host'] as String?,
      tls: (j['tls'] as String?) == 'tls' || (j['tls'] as bool? ?? false),
      sni: j['sni'] as String?,
      alpn: j['alpn'] as String?,
      fingerprint: j['fp'] as String?,
    );
  }

  // -------------------------------------------------------------------------
  // VLESS / Trojan share the same URI shape:
  //   {scheme}://{uuid_or_password}@{host}:{port}?{params}#{remarks}
  // -------------------------------------------------------------------------
  static Profile _parseVlessLike(String uriString, ProtocolType protocol) {
    final Uri uri;
    try {
      uri = Uri.parse(uriString);
    } catch (_) {
      throw FormatException('Cannot parse ${protocol.displayName} URI');
    }
    if (uri.host.isEmpty) {
      throw FormatException('${protocol.displayName} URI is missing host');
    }
    final params = uri.queryParameters;
    return Profile(
      protocol: protocol,
      remarks: Uri.decodeComponent(uri.fragment.isEmpty ? protocol.displayName : uri.fragment),
      address: uri.host,
      port: uri.port,
      userId: protocol == ProtocolType.vless ? Uri.decodeComponent(uri.userInfo) : null,
      password: protocol == ProtocolType.trojan ? Uri.decodeComponent(uri.userInfo) : null,
      network: params['type'] ?? 'tcp',
      security: params['encryption'],
      path: params['path'],
      host: params['host'],
      tls: (params['security'] ?? '').toLowerCase() != 'none' && params['security'] != null,
      sni: params['sni'],
      alpn: params['alpn'],
      flow: params['flow'],
      publicKey: params['pbk'],
      shortId: params['sid'],
      spiderX: params['spx'],
      fingerprint: params['fp'],
    );
  }

  // -------------------------------------------------------------------------
  // Shadowsocks SIP002. Two flavours we accept:
  //   ss://base64(method:password)@host:port#remarks
  //   ss://base64(method:password@host:port)#remarks         (legacy)
  // -------------------------------------------------------------------------
  static Profile _parseShadowsocks(String uri) {
    final body = uri.substring('ss://'.length);
    String userInfoEncoded;
    String hostPart;
    String fragment;

    final hashIdx = body.indexOf('#');
    final atIdx = body.indexOf('@');
    if (atIdx > 0) {
      // SIP002: userinfo @ host
      userInfoEncoded = body.substring(0, atIdx);
      final tail = hashIdx > 0 ? body.substring(atIdx + 1, hashIdx) : body.substring(atIdx + 1);
      hostPart = tail;
      fragment = hashIdx > 0 ? body.substring(hashIdx + 1) : '';
    } else {
      // Legacy: whole thing is base64 of method:password@host:port
      final raw = hashIdx > 0 ? body.substring(0, hashIdx) : body;
      fragment = hashIdx > 0 ? body.substring(hashIdx + 1) : '';
      final decoded = _b64Decode(raw);
      final at = decoded.indexOf('@');
      if (at < 0) throw const FormatException('Malformed legacy ss:// URI');
      userInfoEncoded = base64UrlEncode(utf8.encode(decoded.substring(0, at)));
      hostPart = decoded.substring(at + 1);
    }

    final userInfo = _b64Decode(userInfoEncoded);
    final colonIdx = userInfo.indexOf(':');
    if (colonIdx < 0) throw const FormatException('ss:// userinfo missing method:password');
    final method = userInfo.substring(0, colonIdx);
    final password = userInfo.substring(colonIdx + 1);

    final hostColon = hostPart.lastIndexOf(':');
    if (hostColon < 0) throw const FormatException('ss:// host missing :port');
    final host = hostPart.substring(0, hostColon);
    final port = int.tryParse(hostPart.substring(hostColon + 1)) ?? 0;

    return Profile(
      protocol: ProtocolType.shadowsocks,
      remarks: fragment.isEmpty ? 'Shadowsocks' : Uri.decodeComponent(fragment),
      address: host,
      port: port,
      method: method,
      password: password,
    );
  }

  /// Decodes both standard and URL-safe base64, with permissive padding —
  /// real-world share links from various clients are inconsistent.
  static String _b64Decode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    final pad = (4 - s.length % 4) % 4;
    s = s + ('=' * pad);
    return utf8.decode(base64.decode(s));
  }
}
