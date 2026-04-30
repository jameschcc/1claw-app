import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';
import '../utils/color_utils.dart';

/// Compact metro-style card for each agent profile.
/// Max 200px wide. Long-press/right-click for context menu with pin + info.
/// [compact]=true renders a smaller tile suitable for the right column.
/// Shows unread red dot + last message preview in portrait mode.
class AgentCard extends StatelessWidget {
  final AgentProfile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onTogglePin;
  final bool compact;

  const AgentCard({
    super.key,
    required this.profile,
    required this.isActive,
    required this.onTap,
    this.onTogglePin,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = avatarColor(profile.name);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = profile.status == 'working'
        ? Colors.orangeAccent
        : profile.status == 'starting'
            ? Colors.amber
            : AppConstants.onlineGreen;
    final statusLabel = profile.status == 'working'
        ? 'Working'
        : profile.status == 'starting'
            ? 'Starting...'
            : 'Free';

    if (compact) {
      return _buildCompact(context, color, isDark, statusColor, statusLabel);
    }

    return GestureDetector(
      onTap: profile.online ? onTap : null,
      onLongPress: () => _showContextMenu(context),
      onSecondaryTap: () => _showContextMenu(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        decoration: BoxDecoration(
        color: color,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2)
              : Border.all(
                  color: (isDark ? Colors.white24 : Colors.black12),
                  width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isActive ? 0.3 : 0.08),
              blurRadius: isActive ? 8 : 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Star icon if pinned
                  if (profile.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Icon(CupertinoIcons.star, size: 12, color: Colors.amber),
                    ),
                  // Emoji
                  Text(profile.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 6),
                  // Name
                  Text(
                    profile.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textOnBg(color),
                    ),
                  ),
                  // Last message preview + unread
                  Consumer<ChatProvider>(
                    builder: (context, chatProvider, _) {
                      final lastMsg = chatProvider
                          .getLastMessageForProfile(profile.id);
                      final unread = chatProvider.unreadCount(profile.id);
                      final hasUnread = unread > 0;
                      if (lastMsg.isEmpty && !hasUnread) {
                        return const SizedBox(height: 2); // minimal spacer
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Text(
                          lastMsg.isNotEmpty ? lastMsg : '(new messages)',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.normal,
                            color: hasUnread
                                ? textOnBg(color)
                                : textOnBg(color).withValues(alpha: 0.5),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  // Status + tasks
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.circle_filled, size: 6, color: statusColor),
                      const SizedBox(width: 3),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: textOnBg(color).withValues(alpha: 0.7),
                        ),
                      ),
                      if (profile.online) ...[
                        const SizedBox(width: 8),
                        Icon(CupertinoIcons.list_bullet, size: 10,
                            color: textOnBg(color).withValues(alpha: 0.55)),
                        const SizedBox(width: 2),
                        Text(
                          '${profile.tasksQueue}',
                          style: TextStyle(
                            fontSize: 10,
                            color: textOnBg(color).withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Online indicator (top-left corner)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: profile.online
                      ? AppConstants.onlineGreen
                      : AppConstants.offlineGray,
                  border: Border.all(
                    color: isDark ? AppConstants.darkBg : Colors.white,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            // Unread badge (top-right corner, red dot)
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final unread = chatProvider.unreadCount(profile.id);
                if (unread <= 0) return const SizedBox.shrink();
                return Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: unread > 1 ? null : 12,
                    height: unread > 1 ? null : 12,
                    padding: unread > 1
                        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
                        : null,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: unread > 1 ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius:
                          unread > 1 ? BorderRadius.circular(8) : null,
                    ),
                    child: unread > 1
                        ? Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, Color color, bool isDark,
      Color statusColor, String statusLabel) {
    return GestureDetector(
      onTap: profile.online ? onTap : null,
      onLongPress: () => _showContextMenu(context),
      onSecondaryTap: () => _showContextMenu(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 140, minWidth: 80),
        decoration: BoxDecoration(
        color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.2)
                : (isDark ? Colors.white12 : Colors.black12),
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Emoji
                  Text(profile.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 4),
                  // Name
                  Text(
                    profile.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textOnBg(color),
                    ),
                  ),
                  // Last message preview (compact)
                  Consumer<ChatProvider>(
                    builder: (context, chatProvider, _) {
                      final unread = chatProvider.unreadCount(profile.id);
                      if (unread <= 0) return const SizedBox(height: 1);
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          chatProvider.getLastMessageForProfile(profile.id),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: textOnBg(color),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  // Status dot only (no tasks in compact)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.circle_filled, size: 5, color: statusColor),
                      const SizedBox(width: 2),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: textOnBg(color).withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Unread red dot (compact — top-right)
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final unread = chatProvider.unreadCount(profile.id);
                if (unread <= 0) return const SizedBox.shrink();
                return Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
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
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              // Pin toggle
              ListTile(
                leading: Icon(
                  profile.isPinned ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  color: profile.isPinned ? Colors.amber : null,
                ),
                title: Text(profile.isPinned
                    ? 'Unpin from favorites'
                    : 'Pin as favorite'),
                subtitle: Text(
                  profile.isPinned
                      ? 'Remove from top row'
                      : 'Show at top of list',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onTogglePin?.call();
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              // Description (expandable)
              ExpansionTile(
                leading: const Icon(CupertinoIcons.info),
                title: const Text('Description'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      profile.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
