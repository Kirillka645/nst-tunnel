// Smoke + parser tests for NST Tunnel desktop.
//
// Replaces the default counter test that ships with `flutter create`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nst_tunnel_desktop/data/parsers/uri_parser.dart';
import 'package:nst_tunnel_desktop/data/profile.dart';
import 'package:nst_tunnel_desktop/data/profile_repository.dart';
import 'package:nst_tunnel_desktop/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppTheme', () {
    testWidgets('builds light + dark schemes without throwing', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold()));
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: const Scaffold()));
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('ShareUriParser.isSubscriptionUrl', () {
    test('accepts http and https', () {
      expect(ShareUriParser.isSubscriptionUrl('http://example.com/sub'), isTrue);
      expect(ShareUriParser.isSubscriptionUrl('https://example.com/sub'), isTrue);
    });

    test('rejects share-URI schemes', () {
      expect(ShareUriParser.isSubscriptionUrl('vless://uuid@host:443'), isFalse);
      expect(ShareUriParser.isSubscriptionUrl('ss://YWVzOnB3@host:443'), isFalse);
    });
  });

  group('ShareUriParser.parse — single URI', () {
    test('parses a clean vless:// URI', () {
      final p = ShareUriParser.parse(
        'vless://9e82ed58-f7c5-484c-81aa-89db362bf223@144.31.170.153:443'
        '?encryption=none&flow=xtls-rprx-vision&fp=chrome'
        '&pbk=gBer2H45i735ynkGtcYhGELZXDIf5CfxpE4S_Cl4WGw'
        '&security=reality&sni=www.vk.com&type=tcp#Test%20RU',
      );
      expect(p.protocol, ProtocolType.vless);
      expect(p.address, '144.31.170.153');
      expect(p.port, 443);
      expect(p.userId, '9e82ed58-f7c5-484c-81aa-89db362bf223');
      expect(p.publicKey, 'gBer2H45i735ynkGtcYhGELZXDIf5CfxpE4S_Cl4WGw');
      expect(p.remarks, 'Test RU');
    });

    test('survives malformed RKP-style trailing cruft (",,#" in query)', () {
      // This was the exact pattern that broke parseList in the wild.
      final p = ShareUriParser.parse(
        'vless://75807638-6f19-07d0-ae08-38492ee85c88@178.72.182.20:52006'
        '?type=tcp&headerType=none",,'
        '#SNI%3A%20cl-ru-1.edgeflux.ru',
      );
      expect(p.protocol, ProtocolType.vless);
      expect(p.address, '178.72.182.20');
      expect(p.port, 52006);
    });

    test('throws "Unsupported scheme" for unknown protocols', () {
      expect(
        () => ShareUriParser.parse('socks://user:pass@host:1080'),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported scheme'),
        )),
      );
    });
  });

  group('ShareUriParser.parseList — RKP-style subscription body', () {
    test('handles #-prefixed metadata lines and yields all valid vless URIs', () {
      // Mini fixture mimicking the real RKP url_work.txt structure:
      //   header comments + several share URIs, including a malformed one.
      const body = '''
#profile-title: #РКП
#profile-update-interval: 1
#support-url: https://t.me/RKP_channel
#announce: Свобода заключается в смелости!
#subscription-userinfo: upload=0; download=0; total=0; expire=0
vless://75807638-6f19-07d0-ae08-38492ee85c88@178.72.182.23:52006?encryption=none&flow=xtls-rprx-vision&security=tls&sni=cl-ru-1.edgeflux.ru&type=tcp#A
vless://50b95deb-6394-46c5-b88a-583e5b3ca7ee@fastcon-tgg.harknmav.fun:443?security=reality&sni=max.ru&pbk=PGccrEdFmBaB1rQFJqM-a9jJ1pFsxhUP2sD9KTw5Oz4&sid=f69d7af2d5fc5e0c&type=tcp&flow=xtls-rprx-vision&encryption=none#B
this-is-not-a-uri-and-should-be-ignored
vless://75807638-6f19-07d0-ae08-38492ee85c88@178.72.182.20:52006?type=tcp&headerType=none",,#C
''';

      final profiles = ShareUriParser.parseList(body);

      expect(profiles, hasLength(3));
      expect(profiles[0].address, '178.72.182.23');
      expect(profiles[0].remarks, 'A');
      expect(profiles[1].protocol, ProtocolType.vless);
      expect(profiles[1].address, 'fastcon-tgg.harknmav.fun');
      expect(profiles[2].address, '178.72.182.20');
    });

    test('decodes whole-payload base64 subscriptions', () {
      // base64 of: "vless://aaaa@1.2.3.4:443?security=tls&type=tcp#X\n"
      // Encoded once with standard alphabet.
      const original =
          'vless://aaaa-bbbb-cccc-dddd@1.2.3.4:443?security=tls&type=tcp#X';
      // Use the parser's own base64 path indirectly: feed an encoded body.
      final encoded = _b64(original);
      final profiles = ShareUriParser.parseList(encoded);
      expect(profiles, hasLength(1));
      expect(profiles.first.address, '1.2.3.4');
      expect(profiles.first.remarks, 'X');
    });
  });

  group('ProfileRepository', () {
    test('keeps each imported profile selectable with a unique id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs);

      final profiles = ShareUriParser.parseList('''
vless://aaaa-bbbb-cccc-dddd@1.2.3.4:443?security=tls&type=tcp#A
vless://eeee-ffff-gggg-hhhh@5.6.7.8:443?security=tls&type=tcp#B
vless://iiii-jjjj-kkkk-llll@9.10.11.12:443?security=tls&type=tcp#C
''');

      for (final profile in profiles) {
        await repo.add(profile);
      }

      expect(repo.profiles.map((p) => p.id).toSet(), hasLength(3));
      await repo.setActive(repo.profiles[1].id);
      expect(repo.active?.remarks, 'B');
    });
  });
}

// Local helper: standard base64 (URL-safe alphabet OK too) of an ASCII string.
String _b64(String s) {
  final bytes = s.codeUnits;
  const t = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final n = (bytes[i] << 16) |
        (i + 1 < bytes.length ? bytes[i + 1] << 8 : 0) |
        (i + 2 < bytes.length ? bytes[i + 2] : 0);
    out.write(t[(n >> 18) & 0x3F]);
    out.write(t[(n >> 12) & 0x3F]);
    out.write(i + 1 < bytes.length ? t[(n >> 6) & 0x3F] : '=');
    out.write(i + 2 < bytes.length ? t[n & 0x3F] : '=');
  }
  return out.toString();
}
