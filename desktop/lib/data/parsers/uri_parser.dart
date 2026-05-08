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

  static final _shareUriPattern = RegExp(r'^(vmess|vless|trojan|ss)://');

  static Profile parse(String uri) {
    final trimmed = uri.trim();
    if (trimmed.startsWith('vmess://')) return _parseVmess(trimmed);
    if (trimmed.startsWith('vless://')) return _parseVlessLike(trimmed, ProtocolType.vless);
    if (trimmed.startsWith('trojan://')) return _parseVlessLike(trimmed, ProtocolType.trojan);
    if (trimmed.startsWith('ss://')) return _parseShadowsocks(trimmed);
    throw const FormatException('Unsupported scheme. Expected vmess://, vless://, trojan:// or ss://.');
  }

  /// Detects whether [text] contains a share URI we know how to parse.
  static bool isShareUri(String text) =>
      _shareUriPattern.hasMatch(text.trim());

  /// True iff [text] looks like a `http(s)://` URL — used to decide whether
  /// the input should be treated as a subscription source instead of a
  /// directly-parseable share URI.
  static bool isSubscriptionUrl(String text) {
    final t = text.trim();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  /// Parses multi-line subscription content into a list of [Profile]s.
  ///
  /// Handles every shape we see in the wild:
  ///   * One share URI per line — RKP-style plain-text lists.
  ///   * Whole payload base64-encoded — classic v2rayN / SSR subscription
  ///     format. Auto-detected: if base64-decoding the entire trimmed body
  ///     yields a string containing share URIs, that decoded string is used.
  ///   * Comment / metadata lines starting with `#` — silently skipped
  ///     (e.g. `#profile-title:`, `#subscription-userinfo:` from RKP).
  ///   * Blank lines.
  ///   * Individual malformed URIs — skipped, the rest of the list still
  ///     imports. We never fail a whole batch because of one bad entry.
  static List<Profile> parseList(String content) {
    final body = _maybeBase64Decode(content);

    final profiles = <Profile>[];
    for (final raw in body.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      if (!isShareUri(line)) continue;
      try {
        profiles.add(parse(line));
      } on FormatException {
        // Skip malformed individual URIs but keep importing the rest.
      } catch (_) {
        // Same — never let one bad entry break the whole subscription.
      }
    }
    return profiles;
  }

  /// If [content] looks like a base64-encoded subscription payload AND
  /// decoding yields a string with share URIs in it, return the decoded
  /// text. Otherwise return [content] verbatim. The heuristic intentionally
  /// only swaps when the result is a *better* candidate than the input.
  static String _maybeBase64Decode(String content) {
    final trimmed = content.trim();
    if (_shareUriPattern.hasMatch(trimmed)) return trimmed; // already plain text
    try {
      final decoded = _b64Decode(trimmed);
      if (RegExp(r'(vmess|vless|trojan|ss)://').hasMatch(decoded)) {
        return decoded;
      }
    } catch (_) {/* not base64 — fall through */}
    return trimmed;
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
      uri = Uri.parse(_sanitiseShareUri(uriString));
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

  /// Aggressively sanitises a share URI before handing it to `Uri.parse`.
  ///
  /// Real-world share links are notorious for non-RFC-3986 cruft: stray
  /// `"`, `,`, `\`, embedded JSON like `extra={"host":"",...}`, leftover
  /// closing-quote chains like `headerType=none",,#…`. Java's `URI` and
  /// Dart's `Uri.parse` both refuse those, so we scrub them per RFC 3986
  /// query/fragment rules:
  ///   - Inside the query (between `?` and the LAST `#`): percent-encode
  ///     every byte outside the legal `pchar` set.
  ///   - In the fragment (after `#`): same scrubbing.
  ///   - Path/authority untouched.
  ///
  /// Also normalises space → `%20` and `|` → `%7C` to match the upstream
  /// Android `Utils.fixIllegalUrl`.
  static String _sanitiseShareUri(String input) {
    final qIdx = input.indexOf('?');
    if (qIdx < 0) {
      return input.replaceAll(' ', '%20').replaceAll('|', '%7C');
    }
    // Fragment marker is the LAST '#' so embedded `#` inside query values
    // (very rare but we've seen it) doesn't truncate the query.
    final fIdx = input.lastIndexOf('#');
    final hasFragment = fIdx > qIdx;

    final scheme = input.substring(0, qIdx + 1); // includes the '?'
    final query = hasFragment
        ? input.substring(qIdx + 1, fIdx)
        : input.substring(qIdx + 1);
    final fragmentPart = hasFragment ? input.substring(fIdx) : ''; // includes '#'

    final encodedQuery = _encodeUnsafe(query, _queryAllowed);
    final encodedFragment = fragmentPart.isEmpty
        ? ''
        : '#${_encodeUnsafe(fragmentPart.substring(1), _fragmentAllowed)}';
    return '$scheme$encodedQuery$encodedFragment';
  }

  // RFC 3986 query / fragment allowed sets (excluding percent — already-encoded
  // sequences like `%22` pass through unchanged because `%` is in the set and
  // the trailing two hex chars are ASCII alphanumerics).
  static const _queryAllowed =
      r"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!\$&'()*+,;=:@/?%";
  static const _fragmentAllowed = _queryAllowed;

  static String _encodeUnsafe(String raw, String allowed) {
    final out = StringBuffer();
    for (final code in raw.codeUnits) {
      final ch = String.fromCharCode(code);
      if (allowed.contains(ch) && code < 0x80) {
        out.write(ch);
      } else if (code < 0x80) {
        out.write('%${code.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      } else {
        // Multi-byte UTF-8: encode as bytes.
        for (final b in utf8.encode(ch)) {
          out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
    return out.toString();
  }
}
