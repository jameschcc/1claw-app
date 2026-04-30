import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../config/constants.dart';
import '../models/chat_message.dart';
import 'toast.dart';

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
/// Shows a retry icon on user messages that the agent didn't respond to.
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isReplyTarget;
  final VoidCallback? onReply;
  final String? profileName;
  final bool showRetry;
  final bool isFailed;
  final VoidCallback? onRetry;

  const ChatBubble({
    super.key,
    required this.message,
    this.isReplyTarget = false,
    this.onReply,
    this.profileName,
    this.showRetry = false,
    this.isFailed = false,
    this.onRetry,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isHovered = false;
  bool _showRaw = false;
  double _cachedBubbleMaxWidth = 0;
  Timer? _resizeDebounce;

  @override
  void dispose() {
    _resizeDebounce?.cancel();
    super.dispose();
  }

  void _toggleRawMode() {
    setState(() => _showRaw = !_showRaw);
  }

  /// Build a visual "引用" label for messages that start with a blockquote.
  /// Shows a small label + the quoted text with left border.
  List<Widget> _buildQuoteLabel(bool isDark, bool isUser) {
    final content = widget.message.content;
    // Extract blockquote lines from the beginning
    final lines = content.split('\n');
    final quoteLines = <String>[];
    int i = 0;
    while (i < lines.length && lines[i].startsWith('> ')) {
      quoteLines.add(lines[i].substring(2)); // strip "> " prefix
      i++;
    }

    final quoteBg = isUser
        ? Colors.white.withValues(alpha: 0.10)
        : (isDark ? Colors.black.withValues(alpha: 0.12) : Colors.grey.shade100);
    final quoteBorder = isUser
        ? Colors.white38
        : (isDark ? Colors.white24 : Colors.grey.shade400);
    final quoteText = isUser
        ? Colors.white70
        : (isDark ? Colors.white54 : Colors.black54);

    return [
      // "引用" label
      Row(
        children: [
          Icon(CupertinoIcons.arrowshape_turn_up_left,
              size: 11,
              color: isUser
                  ? Colors.white54
                  : (isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(width: 4),
          Text(
            '引用',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isUser
                  ? Colors.white54
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      // Quoted text block with left border
      Container(
        width: double.infinity,
        padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4, right: 4),
        decoration: BoxDecoration(
          color: quoteBg,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(width: 3, color: quoteBorder),
          ),
        ),
        child: SelectableText(
          quoteLines.join('\n'),
          style: TextStyle(
            fontSize: 12,
            color: quoteText,
            height: 1.4,
          ),
          maxLines: 5,
        ),
      ),
      if (i < lines.length - 1 || (i < lines.length && lines[i].trim().isEmpty)) ...[
        const SizedBox(height: 8),
      ],
    ];
  }

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
    final debugSessionLabel = _buildDebugSessionLabel(widget.message);
    final hasQuote = widget.message.content.startsWith('> ');
    final contentLines = widget.message.content.split('\n');
    int quoteEnd = 0;
    while (quoteEnd < contentLines.length && contentLines[quoteEnd].startsWith('> ')) {
      quoteEnd++;
    }
    // Skip blank lines between quote and reply
    while (quoteEnd < contentLines.length && contentLines[quoteEnd].trim().isEmpty) {
      quoteEnd++;
    }
    final remainingContent = (hasQuote && quoteEnd < contentLines.length)
        ? contentLines.skip(quoteEnd).join('\n').trim()
        : widget.message.content;

    // Compute bubble background color
    final baseBubbleColor = widget.isReplyTarget
        ? (isUser
            ? AppConstants.primaryBlue.withValues(alpha: 0.7)
            : AppConstants.primaryBlue.withValues(alpha: 0.15))
        : isUser
            ? AppConstants.primaryBlue
            : (isDark ? AppConstants.darkCard : Colors.white);

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
          // Retry / error icon for user messages
          if (isUser && widget.showRetry) ...[
            GestureDetector(
              onTap: widget.onRetry,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Tooltip(
                  message: widget.isFailed ? 'Send failed, tap to retry' : 'Resend message',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: widget.isFailed
                          ? Colors.red.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.isFailed
                          ? CupertinoIcons.exclamationmark_circle
                          : CupertinoIcons.refresh,
                      size: 16,
                      color: widget.isFailed
                          ? Colors.red.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Avatar for agent messages
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final newWidth = constraints.maxWidth * 0.80;
                if (newWidth != _cachedBubbleMaxWidth) {
                  _resizeDebounce?.cancel();
                  _resizeDebounce = Timer(const Duration(milliseconds: 100), () {
                    if (mounted) setState(() => _cachedBubbleMaxWidth = newWidth);
                  });
                }
                final bubbleMaxWidth = _cachedBubbleMaxWidth > 0 ? _cachedBubbleMaxWidth : newWidth;
                return GestureDetector(
                  onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
                  onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHovered = true),
                    onExit: (_) => setState(() => _isHovered = false),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: bubbleMaxWidth,
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
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Show "引用" label if content has a quoted reference
                              if (hasQuote && !_showRaw) ..._buildQuoteLabel(isDark, isUser),
                              if (_showRaw)
                                SelectableText(
                                  // In raw mode, show everything as-is
                                  widget.message.content,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                    color: isUser
                                        ? Colors.white
                                        : (isDark ? Colors.white : Colors.black87),
                                  ),
                                )
                              else
                                MarkdownBody(
                                  data: hasQuote ? remainingContent : widget.message.content,
                                  selectable: false,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(
                                      fontSize: 14,
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    code: TextStyle(
                                      fontSize: 13,
                                      backgroundColor: isUser
                                          ? Colors.white24
                                          : (isDark ? Colors.white12 : Colors.grey.shade200),
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.green.shade200 : Colors.red.shade800),
                                    ),
                                    codeblockDecoration: BoxDecoration(
                                      color: isUser
                                          ? Colors.white12
                                          : (isDark ? Colors.black26 : Colors.grey.shade100),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    h1: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    h2: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    h3: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    a: TextStyle(
                                      fontSize: 14,
                                      color: isUser
                                          ? Colors.white70
                                          : (isDark ? Colors.blue.shade200 : Colors.blue),
                                      decoration: TextDecoration.underline,
                                    ),
                                    blockquoteDecoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          width: 3,
                                          color: isUser
                                              ? Colors.white38
                                              : (isDark
                                                  ? Colors.white24
                                                  : Colors.grey.shade400),
                                        ),
                                      ),
                                    ),
                                    listBullet: TextStyle(
                                      fontSize: 14,
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    strong: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    em: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: isUser
                                          ? Colors.white
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    horizontalRuleDecoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: isUser
                                              ? Colors.white24
                                              : (isDark
                                                  ? Colors.white12
                                                  : Colors.grey.shade300),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(widget.message.timestamp),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isUser
                                      ? Colors.white60
                                      : (isDark ? Colors.white38 : Colors.black38),
                                ),
                                textAlign: TextAlign.end,
                              ),
                              if (debugSessionLabel != null) ...[
                                const SizedBox(height: 2),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    debugSessionLabel,
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 9,
                                      height: 1.2,
                                      color: isUser
                                          ? Colors.white54
                                          : (isDark ? Colors.white30 : Colors.black38),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // </> raw mode toggle — Cupertino icon, shown on hover for agent messages
                          if (!widget.message.isUser && _isHovered)
                            Positioned(
                              top: 5,
                              right: 5,
                              child: GestureDetector(
                                onTap: _toggleRawMode,
                                child: Tooltip(
                                  message: _showRaw ? 'View rendered' : 'View raw markdown',
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: _showRaw
                                          ? (isDark ? Colors.blue.shade700 : Colors.blue.shade100)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.chevron_left_slash_chevron_right,
                                      size: 14,
                                      color: _showRaw
                                          ? Colors.blue
                                          : (isDark ? Colors.white54 : Colors.grey.shade500),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    HapticFeedback.mediumImpact();

    // use global overlay area as containing rect so globalPosition aligns correctly
    final overlaySize = MediaQuery.of(context).size;
    final relativeRect = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 1, 1),
      Offset.zero & overlaySize,
    );

    showMenu<String>(
      context: context,
      position: relativeRect,
      items: [
        if (widget.message.isUser && widget.onRetry != null)
          PopupMenuItem<String>(
            value: 'retry',
            child: SizedBox(
              width: 120,
              child: Row(
                children: [
                  Icon(
                    widget.isFailed
                        ? CupertinoIcons.exclamationmark_circle
                        : CupertinoIcons.refresh,
                    size: 18,
                    color: widget.isFailed ? Colors.red.shade600 : null,
                  ),
                  const SizedBox(width: 10),
                  Text(widget.isFailed ? 'Retry' : 'Retry'),
                ],
              ),
            ),
          ),
        PopupMenuItem<String>(
          value: 'copy',
          child: const SizedBox(
            width: 120,
            child: Row(
              children: [
                Icon(CupertinoIcons.doc_on_doc, size: 18),
                SizedBox(width: 10),
                Text('Copy'),
              ],
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'reply',
          child: const SizedBox(
            width: 120,
            child: Row(
              children: [
                Icon(CupertinoIcons.arrowshape_turn_up_left, size: 18),
                SizedBox(width: 10),
                Text('Reply'),
              ],
            ),
          ),
        ),
      ],
    ).then((value) {
      if (!mounted) return;
      switch (value) {
        case 'retry':
          widget.onRetry?.call();
          break;
        case 'copy':
          Clipboard.setData(ClipboardData(text: widget.message.content));
          showToast(context, 'Copied');
          break;
        case 'reply':
          widget.onReply?.call();
          break;
      }
    });
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String? _buildDebugSessionLabel(ChatMessage message) {
    if (!kDebugMode) {
      return null;
    }

    final sessionId = message.sessionId?.trim();
    final requestSessionId = message.requestSessionId?.trim();
    final hasSessionId = sessionId != null && sessionId.isNotEmpty;
    final hasRequestSessionId =
        requestSessionId != null && requestSessionId.isNotEmpty;

    if (!hasSessionId && !hasRequestSessionId) {
      return 'sid: -';
    }

    if (message.isAgent) {
      return 'sid: ${hasSessionId ? sessionId : '-'}\nreq: ${hasRequestSessionId ? requestSessionId : '-'}';
    }

    if (hasRequestSessionId && requestSessionId != sessionId) {
      return 'sid: ${hasSessionId ? sessionId : '-'}\nreq: $requestSessionId';
    }

    return 'sid: ${hasSessionId ? sessionId : '-'}';
  }
}
