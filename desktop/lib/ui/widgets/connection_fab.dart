import 'package:flutter/material.dart';

import '../../service/xray_service.dart';
import '../../theme/app_theme.dart';

/// The big primary action — tap to connect/disconnect the active profile.
/// Visual states match the Android app's FAB:
///   * disconnected → neutral grey + ▶
///   * connecting   → amber + ⟳ (spinning)
///   * connected    → brand orange + ■
///   * failed       → error-red + ⚠
class ConnectionFab extends StatelessWidget {
  const ConnectionFab({
    super.key,
    required this.state,
    required this.enabled,
    required this.onPressed,
  });

  final XrayState state;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (color, fgColor, child, tooltip) = switch (state) {
      XrayState.disconnected => (
          enabled ? AppTheme.disconnectedGrey : scheme.surfaceContainerHigh,
          scheme.onSurface,
          const Icon(Icons.play_arrow_rounded, size: 28),
          'Connect',
        ),
      XrayState.connecting => (
          AppTheme.connectingAmber,
          Colors.black,
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
          ),
          'Connecting…',
        ),
      XrayState.connected => (
          scheme.secondary,
          scheme.onSecondary,
          const Icon(Icons.stop_rounded, size: 26),
          'Disconnect',
        ),
      XrayState.failed => (
          scheme.error,
          scheme.onError,
          const Icon(Icons.refresh_rounded, size: 26),
          'Retry',
        ),
    };

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            if (state == XrayState.connected)
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 16,
                spreadRadius: 2,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: fgColor),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
