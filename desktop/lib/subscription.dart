import 'dart:convert';
import 'package:http/http.dart' as http;

/// Fetches subscription content. Many panels (Marzban, 3x-ui, etc.) ONLY return
/// configs when the request carries a known VPN client User-Agent. We try a few.
class SubscriptionFetcher {
  static const _userAgents = [
    'Happ/2.16.2',
    'v2rayNG/1.9.5',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) NSTTunnel/2.19',
  ];

  /// Returns plain text containing links (already base64-decoded if needed).
  static Future<String> fetch(String url) async {
    http.Response? last;
    for (final ua in _userAgents) {
      try {
        final resp = await http
            .get(Uri.parse(url), headers: {
              'User-Agent': ua,
              'Accept': '*/*',
            })
            .timeout(const Duration(seconds: 20));
        last = resp;
        if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
          final norm = _normalize(resp.body);
          if (norm.contains('://')) return norm;
        }
      } catch (_) {}
    }
    if (last != null) return _normalize(last.body);
    throw Exception('Subscription fetch failed');
  }

  static String _normalize(String body) {
    final trimmed = body.trim();
    if (trimmed.contains('://')) return trimmed;
    try {
      final fixed = base64.normalize(trimmed.replaceAll(RegExp(r'\s'), ''));
      final decoded = utf8.decode(base64.decode(fixed), allowMalformed: true);
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    return trimmed;
  }
}
