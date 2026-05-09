import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Friendly first-run / empty list placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onAddTapped});

  final VoidCallback onAddTapped;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/icons/nst_logo.svg',
                width: 96,
                height: 96,
              ),
              const SizedBox(height: 24),
              Text(
                'No servers yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Paste a vmess://, vless://, trojan:// or ss:// share link to add your first server.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAddTapped,
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Import share link'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
