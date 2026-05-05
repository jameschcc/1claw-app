import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';
import '../utils/color_utils.dart';
import 'toast.dart';

String _avatarLetter(String name) {
  if (name.isEmpty) return '?';
  return name[0].toUpperCase();
}

/// Format a DateTime for the user list timestamp (top-right of each row).
String _formatTimestamp(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final msgDate = DateTime(dt.year, dt.month, dt.day);

  if (msgDate == today) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  } else if (msgDate == yesterday) {
    return 'Yesterday';
  } else if (dt.year == now.year) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } else {
    return '${dt.year.toString().substring(2)}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// Lighten a color by [amount] in HSL lightness space.
Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

/// Darken a color by [amount] in HSL lightness space.
Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

/// A user row in the left sidebar — ~60px height.
/// Left: letter avatar (HSL color). Right: name (top) + last msg preview + unread badge.
/// Hover effect: slight background color shift; selected state: profile color tint.
/// Supports right-click context menu with pin/favorite toggle.
class UserListItem extends StatefulWidget {
  final AgentProfile profile;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onTogglePin;

  const UserListItem({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.onTap,
    this.onTogglePin,
  });

  @override
  State<UserListItem> createState() => _UserListItemState();
}

class _UserListItemState extends State<UserListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Color(widget.profile.colorValue);
    final avatarBg = avatarColor(widget.profile.name);
    final avatarLetter = _avatarLetter(widget.profile.name);

    // Compute background: selected > hover > normal
    Color bgColor;
    if (widget.isSelected) {
      bgColor = color.withValues(alpha: 0.15);
    } else if (_isHovered) {
      bgColor = isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04);
    } else {
      bgColor = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Avatar with unread badge
                Stack(
                  clipBehavior: Clip.none,

                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: avatarBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          avatarLetter,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: avatarBg.computeLuminance() > 0.5
                                ? Colors.black87
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Unread badge (red dot, top-right)
                    Consumer<ChatProvider>(
                      builder: (context, chatProvider, _) {
                        final unread = chatProvider.unreadCount(widget.profile.id);
                        if (unread <= 0) return const SizedBox.shrink();
                        return Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Color.fromARGB(88, 0, 0, 0),
                                  blurRadius: 1,
                                  spreadRadius: .5,
                                ),
                              ],
                              shape: BoxShape.circle,
                              color: Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                // Name + last message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Name row with timestamp on right
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (widget.profile.isPinned)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(CupertinoIcons.star,
                                        size: 11, color: Colors.amber),
                                  ),
                                Flexible(
                                  child: Text(
                                    widget.profile.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: widget.profile.online
                                        ? AppConstants.onlineGreen
                                        : AppConstants.offlineGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Timestamp on the right
                          Consumer<ChatProvider>(
                            builder: (context, chatProvider, _) {
                              final ts = chatProvider
                                  .getLastMessageTimestamp(widget.profile.id);
                              if (ts == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  _formatTimestamp(ts),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Last message preview + unread count
                      Consumer<ChatProvider>(
                        builder: (context, chatProvider, _) {
                          final lastMsg = chatProvider
                              .getLastMessageForProfile(widget.profile.id);
                          final unread = chatProvider.unreadCount(widget.profile.id);
                          final hasUnread = unread > 0;

                          Widget preview;
                          if (lastMsg.isEmpty) {
                            preview = Text(
                              widget.profile.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white38 : Colors.black45,
                              ),
                            );
                          } else {
                            preview = Text(
                              lastMsg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    hasUnread ? FontWeight.w600 : FontWeight.normal,
                                color: hasUnread
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark ? Colors.white38 : Colors.black45),
                              ),
                            );
                          }

                          if (!hasUnread) return preview;

                          return Row(
                            children: [
                              Expanded(child: preview),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  unread > 99 ? '99+' : '$unread',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    HapticFeedback.mediumImpact();

    final relativeRect = RelativeRect.fromLTRB(
      position.dx, position.dy, position.dx + 1, position.dy + 1,
    );

    showMenu<String>(
      context: context,
      position: relativeRect,
      items: [
        PopupMenuItem<String>(
          value: 'pin',
          child: SizedBox(
            width: 160,
            child: Row(
              children: [
                Icon(
                  widget.profile.isPinned
                      ? CupertinoIcons.star_fill
                      : CupertinoIcons.star,
                  size: 18,
                  color: widget.profile.isPinned ? Colors.amber : null,
                ),
                const SizedBox(width: 10),
                Text(widget.profile.isPinned
                    ? 'Unpin from favorites'
                    : 'Pin as favorite'),
              ],
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'description',
          child: const SizedBox(
            width: 160,
            child: Row(
              children: [
                Icon(CupertinoIcons.info, size: 18),
                SizedBox(width: 10),
                Text('Description'),
              ],
            ),
          ),
        ),
      ],
    ).then((value) {
      if (!mounted) return;
      switch (value) {
        case 'pin':
          widget.onTogglePin?.call();
          break;
        case 'description':
          showToast(context, widget.profile.description, duration: const Duration(seconds: 3));
          break;
      }
    });
  }
}
