import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';

/// Compact metro-style card for each agent profile.
/// Max 200px wide. Long-press/right-click for context menu with pin + info.
class AgentCard extends StatelessWidget {
  final AgentProfile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onTogglePin;

  const AgentCard({
    super.key,
    required this.profile,
    required this.isActive,
    required this.onTap,
    this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.colorValue);
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

    return GestureDetector(
      onTap: profile.online ? onTap : null,
      onLongPress: () => _showContextMenu(context),
      onSecondaryTap: () => _showContextMenu(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        decoration: BoxDecoration(
          color: isActive
              ? color
              : (isDark ? AppConstants.darkCard : AppConstants.lightCard),
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
                      color: isActive
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 4),
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
                          color: isActive
                              ? Colors.white70
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                      if (profile.online) ...[
                        const SizedBox(width: 8),
                        Icon(CupertinoIcons.list_bullet, size: 10,
                            color: isActive ? Colors.white54 : Colors.grey),
                        const SizedBox(width: 2),
                        Text(
                          '${profile.tasksQueue}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isActive
                                ? Colors.white54
                                : (isDark ? Colors.white38 : Colors.black38),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Online indicator (top-right)
            Positioned(
              top: 6,
              right: 6,
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
