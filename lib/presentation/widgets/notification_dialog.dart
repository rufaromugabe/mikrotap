import 'package:flutter/material.dart';

enum NotificationType { success, error, warning, info }

class NotificationData {
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;

  NotificationData({
    required this.title,
    required this.message,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// A modern, flat notification dialog for displaying messages
class NotificationDialog extends StatelessWidget {
  final NotificationData notification;

  const NotificationDialog({super.key, required this.notification});

  static Future<void> show(
    BuildContext context,
    NotificationData notification,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => NotificationDialog(notification: notification),
    );
  }

  /// Quick helper for success notifications
  static Future<void> success(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return show(
      context,
      NotificationData(
        title: title,
        message: message,
        type: NotificationType.success,
      ),
    );
  }

  /// Quick helper for error notifications
  static Future<void> error(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return show(
      context,
      NotificationData(
        title: title,
        message: message,
        type: NotificationType.error,
      ),
    );
  }

  /// Quick helper for warning notifications
  static Future<void> warning(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return show(
      context,
      NotificationData(
        title: title,
        message: message,
        type: NotificationType.warning,
      ),
    );
  }

  /// Quick helper for info notifications
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return show(
      context,
      NotificationData(
        title: title,
        message: message,
        type: NotificationType.info,
      ),
    );
  }

  Color _getColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (notification.type) {
      case NotificationType.success:
        return const Color(0xFF10B981); // Green 500
      case NotificationType.error:
        return const Color(0xFFEF4444); // Red 500
      case NotificationType.warning:
        return const Color(0xFFF59E0B); // Amber 500
      case NotificationType.info:
        return cs.primary;
    }
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.error:
        return Icons.error_rounded;
      case NotificationType.warning:
        return Icons.warning_rounded;
      case NotificationType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _getColor(context);
    final icon = _getIcon();

    return Dialog(
      backgroundColor: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.3), width: 1),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with colored accent
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                border: Border(
                  bottom: BorderSide(color: color.withOpacity(0.2), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Got it',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact toast-style notification that appears at the top
class NotificationToast extends StatelessWidget {
  final NotificationData notification;
  final VoidCallback? onDismiss;

  const NotificationToast({
    super.key,
    required this.notification,
    this.onDismiss,
  });

  static void show(
    BuildContext context,
    NotificationData notification, {
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: NotificationToast(
            notification: notification,
            onDismiss: () => entry.remove(),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    // Auto dismiss after duration
    Future.delayed(duration, () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  Color _getColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (notification.type) {
      case NotificationType.success:
        return const Color(0xFF10B981);
      case NotificationType.error:
        return const Color(0xFFEF4444);
      case NotificationType.warning:
        return const Color(0xFFF59E0B);
      case NotificationType.info:
        return cs.primary;
    }
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.error:
        return Icons.error_rounded;
      case NotificationType.warning:
        return Icons.warning_rounded;
      case NotificationType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _getColor(context);
    final icon = _getIcon();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, -20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? cs.surface : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  if (notification.message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
