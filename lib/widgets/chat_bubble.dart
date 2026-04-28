import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/constants.dart';
import '../models/chat_message.dart';

/// Compute HSL background color from first letter of name.
Color _avatarColor(String name) {
  final code = name.isNotEmpty ? name.codeUnitAt(0) : 65;
  final upper = String.fromCharCode(code).toUpperCase().codeUnitAt(0);
  final idx = (upper - 65).clamp(0, 25);
  final hue = (idx / 26.0) * 255.0;
  return HSLColor.fromAHSL(1.0, hue, 0.75, 0.75).toColor();
}

String _avatarLetter(String name) {
  if (name.isEmpty) return '?';
  return name[0].toUpperCase();
}

/// Lighten a color by [amount] in HSL lightness space.
Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

/// Chat message bubble with selectable text, hover highlight,
/// and long-press context menu (Copy / Reply).
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isReplyTarget;
  final VoidCallback? onReply;
  final String? profileName;

  const ChatBubble({
    super.key,
    required this.message,
    this.isReplyTarget = false,
    this.onReply,
    this.profileName,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.isUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = widget.profileName ?? widget.message.profileId;
    final color = _avatarColor(name);
    final letter = _avatarLetter(name);
    final textColor = color.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;

    // Compute bubble background color
    final baseBubbleColor = widget.isReplyTarget
        ? (isUser
            ? AppConstants.primaryBlue.withValues(alpha: 0.7)
            : AppConstants.primaryBlue.withValues(alpha: 0.15))
        : isUser
            ? AppConstants.primaryBlue
            : (isDark ? AppConstants.darkCard : Colors.grey[100]!);

    // Slightly lighten on hover
    final bubbleColor =
        _isHovered ? _lighten(baseBubbleColor, 0.08) : baseBubbleColor;

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
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
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
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
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
                      // Selectable text so users can copy portions
                      SelectableText(
                        widget.message.content,
                        style: TextStyle(
                          fontSize: 14,
                          color: isUser
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(widget.message.timestamp),
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
                  Clipboard.setData(
                      ClipboardData(text: widget.message.content));
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
                  widget.onReply?.call();
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
