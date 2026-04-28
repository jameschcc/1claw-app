import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/thinking_indicator.dart';

/// Chat screen for conversing with a specific agent profile.
class ChatScreen extends StatefulWidget {
  final AgentProfile profile;

  const ChatScreen({super.key, required this.profile});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().switchProfile(widget.profile.id);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      _autoScroll = (max - current) < 80;
    }
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage({String? prepend}) {
    var text = _inputController.text.trim();
    if (prepend != null && text.isNotEmpty) {
      text = '$prepend $text';
    }
    if (text.isEmpty) return;

    final chatProvider = context.read<ChatProvider>();
    chatProvider.clearReplyTarget();
    chatProvider.sendMessage(text);
    _inputController.clear();
    _autoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
      body: Column(
        children: [
          // Messages list + thinking indicator
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                final msgs = chatProvider.messages;
                final thinking = chatProvider.isThinking;

                if (msgs.isEmpty && !thinking) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(widget.profile.emoji,
                            style: const TextStyle(fontSize: 48)),
                        const SizedBox(height: 16),
                        Text(
                          'Start a conversation with\n${widget.profile.name}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: msgs.length + (thinking ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (thinking && index == msgs.length) {
                      return ThinkingIndicator(
                          emoji: widget.profile.emoji,
                          reasoning: chatProvider.reasoningText);
                    }
                    final msg = msgs[index];
                    return ChatBubble(
                      message: msg,
                      isReplyTarget:
                          chatProvider.replyTarget?.id == msg.id,
                      onReply: () =>
                          chatProvider.setReplyTarget(msg),
                    );
                  },
                );
              },
            ),
          ),

          // Reply banner
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              final target = chatProvider.replyTarget;
              if (target == null) return const SizedBox.shrink();
              return Container(
                color: color.withValues(alpha: 0.1),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.reply, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to: ${target.content.length > 40 ? "${target.content.substring(0, 40)}..." : target.content}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: color),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => chatProvider.clearReplyTarget(),
                      child: Icon(Icons.close, size: 16, color: color),
                    ),
                  ],
                ),
              );
            },
          ),

          // Input bar
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppConstants.darkSurface : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1,
                ),
              ),
            ),
            padding: EdgeInsets.only(
              left: 12,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final isThinking = chatProvider.isThinking;
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        enabled: !isThinking,
                        decoration: InputDecoration(
                          hintText:
                              'Message ${widget.profile.name}...',
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : Colors.black38,
                          ),
                          filled: true,
                          fillColor: isThinking
                              ? (isDark
                                  ? AppConstants.darkCard
                                      .withValues(alpha: 0.5)
                                  : Colors.grey[200])
                              : (isDark
                                  ? AppConstants.darkCard
                                  : Colors.grey[100]),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : Colors.black87,
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted:
                            isThinking ? null : (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isThinking
                            ? Colors.grey
                            : color,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          isThinking
                              ? Icons.hourglass_top
                              : Icons.send_rounded,
                          color: Colors.white,
                        ),
                        onPressed:
                            isThinking ? null : _sendMessage,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
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
