import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/parsers/uri_parser.dart';
import '../../data/profile.dart';
import '../../data/subscription_fetcher.dart';

/// Modal for adding servers. Accepts:
///   * one or many share links (vmess/vless/trojan/ss) — one per line
///   * a subscription URL (`https://…`) — fetched and parsed
///   * a base64-encoded subscription payload pasted directly
/// Returns the list of successfully parsed [Profile]s, or null on cancel.
class ImportUriDialog extends StatefulWidget {
  const ImportUriDialog({super.key});

  @override
  State<ImportUriDialog> createState() => _ImportUriDialogState();

  static Future<List<Profile>?> show(BuildContext context) {
    return showDialog<List<Profile>>(
      context: context,
      builder: (_) => const ImportUriDialog(),
    );
  }
}

class _ImportUriDialogState extends State<ImportUriDialog> {
  final _ctl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _ctl.text = data!.text!;
    }
  }

  Future<void> _import() async {
    final raw = _ctl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste at least one share link or a subscription URL');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Subscription URL: fetch + parse list.
      if (ShareUriParser.isSubscriptionUrl(raw)) {
        final profiles = await SubscriptionFetcher.fetch(raw);
        if (profiles.isEmpty) {
          setState(() {
            _busy = false;
            _error = 'Subscription URL returned no usable servers';
          });
          return;
        }
        if (mounted) Navigator.of(context).pop(profiles);
        return;
      }

      // One or many share URIs (or base64 payload) pasted directly.
      final profiles = ShareUriParser.parseList(raw);
      if (profiles.isEmpty) {
        // Try a single-URI fallback so a bare malformed link surfaces a
        // proper error instead of "no usable servers".
        try {
          profiles.add(ShareUriParser.parse(raw));
        } on FormatException catch (e) {
          setState(() {
            _busy = false;
            _error = e.message;
          });
          return;
        }
      }
      if (mounted) Navigator.of(context).pop(profiles);
    } on FormatException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import servers'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 480, maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste any of:\n'
              '  • One or more share links (vmess://, vless://, trojan://, ss://) — one per line\n'
              '  • A subscription URL (https://…) — will be fetched and parsed\n'
              '  • A base64-encoded subscription payload',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctl,
              minLines: 4,
              maxLines: 10,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                hintText:
                    'vmess://eyJ2I…\ntrojan://password@host:443?…\nhttps://example.com/sub',
                errorText: _error,
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _busy ? null : _pasteFromClipboard,
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Fetching subscription…'),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Import'),
        ),
      ],
    );
  }
}
