import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';

/// A user row in the left sidebar — ~60px height.
/// Left: emoji avatar (circle). Right: name (top) + last msg preview (bottom, 1 line).
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
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.3)
                      : (isDark ? AppConstants.darkCard : Colors.grey[200]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    profile.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
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
                    // Last message preview
                    Consumer<ChatProvider>(
                      builder: (context, chatProvider, _) {
                        final lastMsg = chatProvider
                            .getLastMessageForProfile(profile.id);
                        if (lastMsg.isEmpty) {
                          return Text(
                            profile.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          );
                        }
                        return Text(
                          lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
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
