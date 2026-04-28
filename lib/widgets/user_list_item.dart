import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';

/// Compute HSL background color from first letter of name.
/// hue = ((code - 65) / 26) * 255, saturation=0.75, lightness=0.75
Color _avatarColor(String name) {
  final code = name.isNotEmpty ? name.codeUnitAt(0) : 65; // default 'A'
  final upper = String.fromCharCode(code).toUpperCase().codeUnitAt(0);
  final idx = (upper - 65).clamp(0, 25);
  final hue = (idx / 26.0) * 255.0;
  return HSLColor.fromAHSL(1.0, hue, 0.75, 0.75).toColor();
}

String _avatarLetter(String name) {
  if (name.isEmpty) return '?';
  return name[0].toUpperCase();
}

/// A user row in the left sidebar — ~60px height.
/// Left: letter avatar (HSL color). Right: name (top) + last msg preview + unread badge.
class UserListItem extends StatelessWidget {
  final AgentProfile profile;
  final bool isSelected;
  final VoidCallback onTap;

  const UserListItem({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Color(profile.colorValue);
    final avatarBg = _avatarColor(profile.name);
    final avatarLetter = _avatarLetter(profile.name);

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: isSelected
            ? color.withValues(alpha: 0.15)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Avatar with unread badge
              Stack(
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
                      final unread = chatProvider.unreadCount(profile.id);
                      if (unread <= 0) return const SizedBox.shrink();
                      return Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 10,
                          height: 10,
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
              const SizedBox(width: 10),
              // Name + last message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Name row
                    Row(
                      children: [
                        if (profile.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.star,
                                size: 11, color: Colors.amber),
                          ),
                        Flexible(
                          child: Text(
                            profile.name,
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
                            color: profile.online
                                ? AppConstants.onlineGreen
                                : AppConstants.offlineGray,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Last message preview + unread count
                    Consumer<ChatProvider>(
                      builder: (context, chatProvider, _) {
                        final lastMsg = chatProvider
                            .getLastMessageForProfile(profile.id);
                        final unread = chatProvider.unreadCount(profile.id);
                        final hasUnread = unread > 0;

                        Widget preview;
                        if (lastMsg.isEmpty) {
                          preview = Text(
                            profile.description,
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
    );
  }
}
