import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/constants.dart';
import '../models/chat_message.dart';

/// Chat message bubble with long-press context menu (Copy / Reply).
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isReplyTarget;
  final VoidCallback? onReply;

  const ChatBubble({
    super.key,
    required this.message,
    this.isReplyTarget = false,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDark ? AppConstants.darkCard : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  message.profileId.isNotEmpty
                      ? String.fromCharCode(
                              message.profileId.codeUnitAt(0))
                          .toUpperCase()
                      : 'A',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showContextMenu(context),
              onSecondaryTap: () => _showContextMenu(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: isReplyTarget
                      ? (isUser
                          ? AppConstants.primaryBlue.withValues(alpha: 0.7)
                          : AppConstants.primaryBlue.withValues(alpha: 0.15))
                      : isUser
                          ? AppConstants.primaryBlue
                          : (isDark
                              ? AppConstants.darkCard
                              : Colors.grey[100]),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: isUser
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: isUser
                            ? Colors.white60
                            : (isDark
                                ? Colors.white38
                                : Colors.black38),
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
