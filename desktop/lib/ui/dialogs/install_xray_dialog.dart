import 'package:flutter/material.dart';

import '../../service/xray_service.dart';

/// Walks the user through downloading the Xray-core binary on first run.
///
/// Closes itself and returns `true` on success, `false` on cancel/failure.
class InstallXrayDialog extends StatefulWidget {
  const InstallXrayDialog({super.key, required this.service});

  final XrayService service;

  @override
  State<InstallXrayDialog> createState() => _InstallXrayDialogState();

  static Future<bool> show(BuildContext context, XrayService service) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => InstallXrayDialog(service: service),
        ) ??
        false;
  }
}

class _InstallXrayDialogState extends State<InstallXrayDialog> {
  bool _running = false;
  double _progress = 0.0;
  String? _error;
  bool _done = false;

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
      _progress = 0.0;
    });
    try {
      await widget.service.installBinary(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _done = true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install Xray-core'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 420, maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'NST Tunnel needs the Xray-core binary to make connections. '
              'It will be downloaded from the official XTLS/Xray-core GitHub release '
              'and saved to your local app data folder. ~10–20 MB.',
            ),
            const SizedBox(height: 16),
            if (_running && !_done) ...[
              LinearProgressIndicator(value: _progress.clamp(0.0, 1.0)),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)} %'),
            ],
            if (_done)
              const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Installed!'),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_running || _error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        if (!_running || _error != null)
          FilledButton(
            onPressed: _start,
            child: Text(_error == null ? 'Download' : 'Retry'),
          ),
      ],
    );
  }
}
