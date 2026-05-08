import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/parsers/uri_parser.dart';
import '../../data/profile.dart';

/// Modal sheet for pasting one or many share-URIs at once.
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

  void _import() {
    final lines = _ctl.text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      setState(() => _error = 'Paste at least one share link');
      return;
    }
    final profiles = <Profile>[];
    final failures = <String>[];
    for (final line in lines) {
      try {
        profiles.add(ShareUriParser.parse(line));
      } on FormatException catch (e) {
        failures.add('${e.message}: $line');
      }
    }
    if (profiles.isEmpty) {
      setState(() => _error = failures.first);
      return;
    }
    Navigator.of(context).pop(profiles);
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
              'Paste one or more share links (vmess://, vless://, trojan://, ss://). One per line.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctl,
              minLines: 4,
              maxLines: 10,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'vmess://eyJ2I…\ntrojan://password@host:443?…',
                errorText: _error,
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Import'),
        ),
      ],
    );
  }
}
