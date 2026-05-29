// lib/widgets/common/offline_banner.dart
// v24 — A consistent "You're offline" banner that any page can wrap around
// its scaffold body.  Subscribes to ConnectivityService.

import 'package:flutter/material.dart';
import '../../services/connectivity_service.dart';

class OfflineBanner extends StatelessWidget {
  /// The body the banner sits above.
  final Widget child;

  /// Optional override — if true the banner is always shown regardless of
  /// connectivity (useful for forcing "showing cached data" in screens that
  /// know they're rendering from cache).
  final bool forceVisible;

  /// Optional override text — defaults to "You're offline. Showing cached
  /// data." when `forceVisible == false`, or whatever you pass when true.
  final String? messageOverride;

  const OfflineBanner({
    super.key,
    required this.child,
    this.forceVisible = false,
    this.messageOverride,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (ctx, online, _) {
        final showBanner = forceVisible || !online;
        return Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: showBanner
                  ? _buildBanner(ctx, online)
                  : const SizedBox.shrink(),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }

  Widget _buildBanner(BuildContext context, bool online) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = online
        ? (isDark ? const Color(0xFF1F3A1F) : const Color(0xFFE7F5E7))
        : (isDark ? const Color(0xFF3F1F1F) : const Color(0xFFFEF2F2));
    final fg = online
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    final icon = online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded;
    final text = messageOverride ??
        (online
            ? 'Showing cached data — pull to refresh'
            : 'You\'re offline. Showing last cached data.');

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small inline pill version that fits next to a page title / sliver header.
class OfflinePill extends StatelessWidget {
  const OfflinePill({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (_, online, __) {
        if (online) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withAlpha(28),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.cloud_off_rounded, size: 12, color: Color(0xFFDC2626)),
              SizedBox(width: 4),
              Text('Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  )),
            ],
          ),
        );
      },
    );
  }
}
