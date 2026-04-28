import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';
import 'chat_bubble.dart';
import 'thinking_indicator.dart';

/// Reusable chat panel — the core chat UI without Scaffold/AppBar.
/// Used in the landscape sidebar layout or embedded in ChatScreen.
///
/// Uses [ListView.builder] with `reverse: true` so messages grow from the
/// bottom naturally — no need for scrollToBottom hacks.
class ChatPanel extends StatefulWidget {
  final AgentProfile profile;

  const ChatPanel({super.key, required this.profile});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  bool _autoScroll = true;
  bool _initialScrollDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _switchToProfile(widget.profile.id);
    });
    _scrollController.addListener(_onScroll);
    _inputFocus.onKeyEvent = _onKeyEvent;
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _initialScrollDone = false;
      _inputController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _switchToProfile(widget.profile.id);
        _inputFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _switchToProfile(String profileId) {
    context.read<ChatProvider>().switchProfile(profileId);
    // reverse:true — ListView naturally starts at bottom, no scroll needed
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (!HardwareKeyboard.instance.isShiftPressed) {
        _sendMessage();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      // In reverse mode: pixels=0 is bottom (newest), maxScrollExtent is top
      _autoScroll = _scrollController.position.pixels < 80;
    }
  }

  /// Scroll to bottom (pixel 0 in reverse mode).
  void _scrollToBottom({bool force = false}) {
    if ((_autoScroll || force) && _scrollController.hasClients) {
      _scrollController.animateTo(
        0,
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

  /// Retry sending a message that the agent didn't respond to.
  void _retryMessage(String content) {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.sendMessage(content);
    _autoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _confirmCancel() async {
    final shouldCancel =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('中止回答？'),
            content: const Text('当前 agent 正在回复。要立即中止这次回答吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('继续等待'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('中止'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldCancel || !mounted) return;
    context.read<ChatProvider>().cancelActiveResponse();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Color(profile.colorValue);

    return Column(
      children: [
        // Profile header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppConstants.darkSurface : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(profile.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
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
                      const SizedBox(width: 4),
                      Text(
                        profile.online ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          color: profile.online
                              ? AppConstants.onlineGreen
                              : AppConstants.offlineGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Messages + thinking — reverse ListView grows from bottom
        Expanded(
          child: Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              // One-time scroll after history loads (belt & suspenders)
              if (chatProvider.isLoaded && !_initialScrollDone) {
                _initialScrollDone = true;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scrollToBottom(force: true),
                );
              }

              final msgs = chatProvider.messages;
              final thinking = chatProvider.isThinking;
              final hasReasoning = chatProvider.reasoningText.trim().isNotEmpty;

              if (msgs.isEmpty && !thinking && !hasReasoning) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(profile.emoji, style: const TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      Text(
                        'Start a conversation with\n${profile.name}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                reverse: true,
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: msgs.length + ((thinking || hasReasoning) ? 1 : 0),
                itemBuilder: (context, index) {
                  // In reverse mode, index 0 = bottom (most recent)
                  // Thinking indicator is the newest item
                  if ((thinking || hasReasoning) && index == 0) {
                    return ThinkingIndicator(
                      emoji: profile.emoji,
                      reasoning: chatProvider.reasoningText,
                      isActive: thinking,
                    );
                  }
                  // Map ListView index to original msgs index (oldest → newest)
                  final msgOffset = thinking ? index - 1 : index;
                  final msgIndex = msgs.length - 1 - msgOffset;
                  final msg = msgs[msgIndex];

                  // Show retry on user messages where agent didn't respond:
                  // - newest message and not thinking (agent finished but no reply)
                  // - next message is also user (agent skipped this one)
                  final needsRetry =
                      msg.isUser &&
                      ((msgIndex == msgs.length - 1 && !thinking) ||
                          (msgIndex < msgs.length - 1 &&
                              msgs[msgIndex + 1].isUser));
                  return ChatBubble(
                    message: msg,
                    profileName: profile.name,
                    isReplyTarget: chatProvider.replyTarget?.id == msg.id,
                    onReply: () => chatProvider.setReplyTarget(msg),
                    showRetry: needsRetry,
                    onRetry: needsRetry
                        ? () => _retryMessage(msg.content)
                        : null,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Replying to: ${target.content.length > 40 ? "${target.content.substring(0, 40)}..." : target.content}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: color),
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
                      focusNode: _inputFocus,
                      enabled: !isThinking,
                      decoration: InputDecoration(
                        hintText: 'Message ${profile.name}...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        filled: true,
                        fillColor: isThinking
                            ? (isDark
                                  ? AppConstants.darkCard.withValues(alpha: 0.5)
                                  : Colors.grey[200])
                            : (isDark
                                  ? AppConstants.darkCard
                                  : Colors.grey[100]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 4,
                      minLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: isThinking ? Colors.grey : color,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        isThinking ? Icons.hourglass_top : Icons.send_rounded,
                        color: Colors.white,
                      ),
                      onPressed: isThinking ? _confirmCancel : _sendMessage,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
