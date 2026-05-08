import 'dart:io';

import 'package:http/http.dart' as http;

import 'parsers/uri_parser.dart';
import 'profile.dart';

/// Downloads the body of a subscription URL and turns it into [Profile]s.
///
/// We're permissive on purpose:
///   * Any HTTP 2xx is accepted — some hosts (Cloudflare workers, GitHub raw)
///     respond with `Content-Type: text/plain; charset=utf-8` which the http
///     package handles fine.
///   * The body is fed straight into [ShareUriParser.parseList] so it doesn't
///     matter whether it's a base64 blob, a plain-text list, or has comment
///     headers (`#profile-title:`, `#subscription-userinfo:`).
///   * Network/format errors throw a [FormatException] with a human message
///     suitable for surfacing in a SnackBar.
class SubscriptionFetcher {
  SubscriptionFetcher._();

  /// Identifies the client to upstream subscription hosts. Some providers
  /// gate content behind UA whitelists — `v2rayNG` is the most widely
  /// recognised value across the Xray ecosystem.
  static const _userAgent = 'v2rayNG/2.17 (NST Tunnel desktop)';

  /// Total time we'll wait for the request, including TLS + redirects.
  static const _timeout = Duration(seconds: 20);

  /// Fetches [url] and parses the body into a list of [Profile]s.
  /// Returns an empty list iff the body is reachable but contains nothing
  /// that resembles a share URI; throws on transport errors.
  static Future<List<Profile>> fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Subscription URL must start with http:// or https://');
    }

    final http.Response res;
    try {
      res = await http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(_timeout);
    } on SocketException catch (e) {
      throw FormatException('Network error: ${e.message}');
    } on HttpException catch (e) {
      throw FormatException('HTTP error: ${e.message}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FormatException(
        'Subscription server returned HTTP ${res.statusCode}',
      );
    }
    if (res.body.trim().isEmpty) {
      throw const FormatException('Subscription URL returned an empty response');
    }

    return ShareUriParser.parseList(res.body);
  }
}
