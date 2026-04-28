import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';

/// Compact metro-style card for each agent profile.
/// Max 200px wide. Shows status (working/free) and tasks queue in small font.
class AgentCard extends StatelessWidget {
  final AgentProfile profile;
  final bool isActive;
  final VoidCallback onTap;

  const AgentCard({
    super.key,
    required this.profile,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.colorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = profile.status == 'working'
        ? Colors.orangeAccent
        : AppConstants.onlineGreen;
    final statusLabel = profile.status == 'working' ? 'Working' : 'Free';

    return GestureDetector(
      onTap: profile.online ? onTap : null,
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
                  // Status + tasks on one line
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle, size: 6, color: statusColor),
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
                        Icon(Icons.list_alt, size: 10,
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
}
