import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_panel.dart';

/// Chat screen for conversing with a specific agent profile.
/// Used in portrait mode with full-page navigation (AppBar + back button).
/// Embeds the reusable ChatPanel widget.
class ChatScreen extends StatefulWidget {
  final AgentProfile profile;

  const ChatScreen({super.key, required this.profile});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  Widget build(BuildContext context) {
    final color = Color(widget.profile.colorValue);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(widget.profile.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.profile.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text(
                  widget.profile.online ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.profile.online
                        ? AppConstants.onlineGreen
                        : AppConstants.offlineGray,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showOptions(context),
          ),
        ],
        backgroundColor: color.withValues(alpha: 0.15),
      ),
      body: ChatPanel(profile: widget.profile, showHeader: false),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_sweep),
              title: const Text('Clear conversation'),
              onTap: () {
                Navigator.pop(ctx);
                context.read<ChatProvider>().clearConversation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('About ${widget.profile.name}'),
              subtitle: Text(widget.profile.description),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}
