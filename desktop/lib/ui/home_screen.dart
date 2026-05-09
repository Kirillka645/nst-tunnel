import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/parsers/uri_parser.dart';
import '../data/profile.dart';
import '../data/profile_repository.dart';
import '../service/xray_service.dart';
import '../theme/app_theme.dart';
import 'dialogs/import_uri_dialog.dart';
import 'dialogs/install_xray_dialog.dart';
import 'widgets/connection_fab.dart';
import 'widgets/empty_state.dart';
import 'widgets/server_card.dart';

/// Single-screen MVP layout:
///   ┌─────────────────────────────────────┐
///   │  AppBar (NST Tunnel · status pill)  │
///   ├─────────────────────────────────────┤
///   │  Server list (or empty state)       │
///   │                                     │
///   │                                          (FAB) │
///   └─────────────────────────────────────┘
///
/// The AppBar pill mirrors the bottom test-status bar from the Android app:
/// shows "Connected", "Connecting", "Not connected" or the last error.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProfileRepository>();
    final xray = context.watch<XrayService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'NST Tunnel',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 12),
            _StatusPill(state: xray.state, error: xray.lastError),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Paste from clipboard',
            icon: const Icon(Icons.content_paste_go_rounded),
            onPressed: _quickImportFromClipboard,
          ),
          IconButton(
            tooltip: 'Add server…',
            icon: const Icon(Icons.add_link_rounded),
            onPressed: _showImportDialog,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: repo.profiles.isEmpty
          ? EmptyState(onAddTapped: _showImportDialog)
          : _ServerList(
              profiles: repo.profiles,
              activeId: repo.activeId,
              isConnected: xray.isRunning,
              onTap: (p) => repo.setActive(p.id),
              onDelete: (p) => _confirmDelete(p),
            ),
      floatingActionButton: ConnectionFab(
        state: xray.state,
        enabled: repo.active != null,
        onPressed: () => _toggleConnection(repo, xray),
      ),
    );
  }

  Future<void> _toggleConnection(
    ProfileRepository repo,
    XrayService xray,
  ) async {
    if (xray.state == XrayState.connecting) return;

    if (xray.isRunning) {
      await xray.disconnect();
      return;
    }
    final active = repo.active;
    if (active == null) return;

    if (!await xray.isBinaryInstalled()) {
      if (!mounted) return;
      final installed = await InstallXrayDialog.show(context, xray);
      if (!installed) return;
    }
    await xray.connect(active);
    if (!mounted) return;
    if (xray.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(xray.lastError!),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }

  Future<void> _showImportDialog() async {
    final result = await ImportUriDialog.show(context);
    if (result == null || result.isEmpty) return;
    if (!mounted) return;
    final repo = context.read<ProfileRepository>();
    for (final p in result) {
      await repo.add(p);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${result.length} server(s)')),
    );
  }

  Future<void> _quickImportFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text == null) return;
    final text = data!.text!.trim();
    if (!ShareUriParser.isShareUri(text)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard does not contain a share link')),
      );
      return;
    }
    try {
      final profile = ShareUriParser.parse(text);
      if (!mounted) return;
      await context.read<ProfileRepository>().add(profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${profile.remarks}"')),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmDelete(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete server?'),
        content: Text('"${p.remarks}" will be removed permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<ProfileRepository>().remove(p.id);
    }
  }

  Future<void> _showSettings() async {
    final xray = context.read<XrayService>();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Settings'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 420, maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<bool>(
                future: xray.isBinaryInstalled(),
                builder: (context, snap) {
                  final installed = snap.data ?? false;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      installed ? Icons.check_circle_outline : Icons.download_rounded,
                      color: installed
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.secondary,
                    ),
                    title: const Text('Xray-core binary'),
                    subtitle: Text(installed ? 'Installed' : 'Not installed'),
                    trailing: TextButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await InstallXrayDialog.show(context, xray);
                        if (mounted) setState(() {});
                      },
                      child: Text(installed ? 'Reinstall' : 'Install'),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                subtitle: const Text('NST Tunnel desktop · v1.0.0'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ServerList extends StatelessWidget {
  const _ServerList({
    required this.profiles,
    required this.activeId,
    required this.isConnected,
    required this.onTap,
    required this.onDelete,
  });

  final List<Profile> profiles;
  final String? activeId;
  final bool isConnected;
  final void Function(Profile) onTap;
  final void Function(Profile) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), // 96 reserves space under FAB
      itemCount: profiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = profiles[i];
        return ServerCard(
          profile: p,
          isActive: p.id == activeId,
          isConnected: isConnected,
          onTap: () => onTap(p),
          onDelete: () => onDelete(p),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.error});
  final XrayState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (state) {
      XrayState.connected => (
          'Connected',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      XrayState.connecting => (
          'Connecting…',
          AppTheme.connectingAmber.withValues(alpha: 0.25),
          scheme.onSurface,
        ),
      XrayState.disconnected => (
          'Idle',
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
      XrayState.failed => (
          error == null ? 'Failed' : 'Failed: ${_short(error!)}',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  static String _short(String s) => s.length > 30 ? '${s.substring(0, 30)}…' : s;
}
