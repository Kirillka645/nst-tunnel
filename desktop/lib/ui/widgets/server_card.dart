import 'package:flutter/material.dart';

import '../../data/profile.dart';

/// One row in the server list. Tapping selects the profile (becomes "active"
/// for the FAB to connect to), the trailing menu lets the user delete it.
class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.profile,
    required this.isActive,
    required this.isConnected,
    required this.onTap,
    required this.onDelete,
  });

  final Profile profile;
  final bool isActive;
  final bool isConnected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final statusColor = isActive && isConnected
        ? scheme.tertiary
        : isActive
            ? scheme.secondary
            : scheme.outline;

    return Material(
      color: isActive ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Status dot — green when this profile is the live one,
              // orange when it's the selected target, neutral otherwise.
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: isActive && isConnected
                      ? [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.remarks,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.protocol.displayName} · ${profile.address}:${profile.port}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (profile.tls)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'TLS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More',
                onPressed: () => _showMenu(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (choice == 'delete') onDelete();
  }
}
