import 'package:flutter/material.dart';
import '../config/constants.dart';

/// Connection status indicator widget.
/// Shows a dot + text indicating WebSocket connection state.
class ConnectionIndicator extends StatelessWidget {
  final bool isConnected;
  final VoidCallback? onRetry;

  const ConnectionIndicator({
    super.key,
    required this.isConnected,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected
            ? AppConstants.onlineGreen.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? AppConstants.onlineGreen
                  : Colors.red,
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: AppConstants.onlineGreen
                            .withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isConnected
                  ? AppConstants.onlineGreen
                  : Colors.red,
            ),
          ),
          if (!isConnected && onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRetry,
              child: const Icon(
                Icons.refresh,
                size: 16,
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
