import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';

/// Metro-style card widget for each agent profile.
/// Shows emoji, name, and online status in a colorful tile.
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive
              ? color
              : (isDark ? AppConstants.darkCard : AppConstants.lightCard),
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2)
              : Border.all(
                  color: (isDark ? Colors.white24 : Colors.black12),
                  width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isActive ? 0.3 : 0.1),
              blurRadius: isActive ? 12 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Emoji
                  Text(
                    profile.emoji,
                    style: TextStyle(
                      fontSize: isActive ? 40 : 36,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Name
                  Text(
                    profile.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Description
                  Text(
                    profile.description,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? Colors.white70
                          : (isDark ? Colors.white54 : Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
            // Online indicator
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: profile.online
                      ? AppConstants.onlineGreen
                      : AppConstants.offlineGray,
                  border: Border.all(
                    color: isDark ? AppConstants.darkBg : Colors.white,
                    width: 2,
                  ),
                  boxShadow: profile.online
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
            ),
          ],
        ),
      ),
    );
  }
}
