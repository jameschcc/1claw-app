import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';
import 'chat_bubble.dart';
import 'thinking_indicator.dart';
import 'win11_dialog.dart';

/// Reusable chat panel — the core chat UI without Scaffold/AppBar.
/// Used in the landscape sidebar layout or embedded in ChatScreen.
///
/// Uses [ListView.builder] with `reverse: true` so messages grow from the
/// bottom naturally — no need for scrollToBottom hacks.
class ChatPanel extends StatefulWidget {
  final AgentProfile profile;
  final bool showHeader;

  const ChatPanel({
    super.key,
    required this.profile,
    this.showHeader = true,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  bool _autoScroll = true;
  bool _initialScrollDone = false;
  bool _showScrollToBottom = false;
  bool _hoveringStop = false;

  // Input history for Up/Down arrow navigation
  final List<String> _inputHistory = [];
  int _historyIndex = -1; // -1 = current text, 0 = oldest, N-1 = newest
  String _currentDraft = ''; // saved current input when navigating history

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _switchToProfile(widget.profile.id);
      _restoreDraft();
    });
    _scrollController.addListener(_onScroll);
    _inputFocus.onKeyEvent = _onKeyEvent;
  }

  void _restoreDraft() {
    final draft = context.read<ChatProvider>().getDraft(widget.profile.id);
    if (draft.isNotEmpty) {
      _inputController.text = draft;
      // Move cursor to end
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: draft.length),
      );
    }
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      // Save draft for the old profile before switching
      context
          .read<ChatProvider>()
          .saveDraft(oldWidget.profile.id, _inputController.text);
      _initialScrollDone = false;
      _autoScroll = true;
      _showScrollToBottom = false;
      _inputController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _switchToProfile(widget.profile.id);
        _restoreDraft();
        _inputFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _saveDraft();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _saveDraft() {
    if (mounted && context.mounted) {
      context
          .read<ChatProvider>()
          .saveDraft(widget.profile.id, _inputController.text);
    }
  }

  void _switchToProfile(String profileId) {
    context.read<ChatProvider>().switchProfile(profileId);
    _requestHistory();
    _inputHistory.clear();
    _historyIndex = -1;
    _currentDraft = '';
    // reverse:true — ListView naturally starts at bottom, no scroll needed
  }

  void _requestHistory({bool force = false}) {
    unawaited(context.read<ChatProvider>().requestHistory(force: force));
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Enter — send message (unless Shift held for multi-line)
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (!HardwareKeyboard.instance.isShiftPressed) {
          _sendMessage();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      // ArrowUp — navigate input history (older)
      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          !HardwareKeyboard.instance.isShiftPressed &&
          _inputHistory.isNotEmpty) {
        // First time pressing Up: save current input
        if (_historyIndex == -1) {
          _currentDraft = _inputController.text;
        }
        if (_historyIndex < _inputHistory.length - 1) {
          _historyIndex++;
          _inputController.text =
              _inputHistory[_inputHistory.length - 1 - _historyIndex];
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        }
        return KeyEventResult.handled;
      }

      // ArrowDown — navigate input history (newer)
      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          !HardwareKeyboard.instance.isShiftPressed &&
          _historyIndex >= 0) {
        _historyIndex--;
        if (_historyIndex >= 0) {
          _inputController.text =
              _inputHistory[_inputHistory.length - 1 - _historyIndex];
        } else {
          // Back to user's current draft
          _inputController.text = _currentDraft;
          _currentDraft = '';
        }
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      // In reverse mode: pixels=0 is bottom (newest), maxScrollExtent is top
      final nextAutoScroll = _scrollController.position.pixels < 80;
      if (nextAutoScroll != _autoScroll || _showScrollToBottom == nextAutoScroll) {
        setState(() {
          _autoScroll = nextAutoScroll;
          _showScrollToBottom = !nextAutoScroll;
        });
      }
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
    final chatProvider = context.read<ChatProvider>();
    if (chatProvider.isThinking) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在等待回复，请稍等'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    var text = _inputController.text.trim();
    if (prepend != null && text.isNotEmpty) {
      text = '$prepend $text';
    }
    if (text.isEmpty) return;
    chatProvider.clearReplyTarget();
    chatProvider.sendMessage(text);
    chatProvider.saveDraft(widget.profile.id, '');
    _inputController.clear();
    // Push to input history
    _inputHistory.add(text);
    if (_inputHistory.length > 100) {
      _inputHistory.removeAt(0);
    }
    _historyIndex = -1;
    _currentDraft = '';
    _autoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Retry sending a message that the agent didn't respond to.
  void _retryMessage(String msgId, String content) {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.retryMessage(msgId);
    _autoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _confirmCancel() async {
    final shouldCancel = await Win11Dialog.show(
      context,
      title: '中止回答？',
      content: '当前 agent 正在回复。要立即中止这次回答吗？',
      confirmText: '中止',
      cancelText: '继续等待',
      accentColor: Color(0xFFE81123), // Win11 red accent
      icon: const Icon(CupertinoIcons.clear_circled,
          size: 32, color: Color(0xFFE81123)),
    );

    if (!shouldCancel || !mounted) return;
    context.read<ChatProvider>().cancelActiveResponse();
  }

  Widget _buildOverlayActionButton({
    required bool isDark,
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final foreground = isDark ? Colors.white70 : Colors.black54;
    final background = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Icon(icon, size: 18, color: foreground),
        ),
      ),
    );

    if (tooltip == null || tooltip.isEmpty) {
      return button;
    }

    return Tooltip(message: tooltip, child: button);
  }

  Widget _buildEmptyState(bool isDark, AgentProfile profile, bool isLoading) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(profile.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            isLoading
                ? 'Loading conversation history...'
                : 'Start a conversation with\n${profile.name}',
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

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Color(profile.colorValue);

    return Column(
      children: [
        // Profile header bar
        if (widget.showHeader)
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
          child: Container(
            color: isDark ? AppConstants.darkBg : AppConstants.lightBg,
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
              final isLoadingHistory = chatProvider.isRequestingHistory;

              if (chatProvider.isLoaded &&
                  msgs.isEmpty &&
                  !thinking &&
                  !hasReasoning &&
                  !isLoadingHistory) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final provider = context.read<ChatProvider>();
                  if (provider.currentProfileId == profile.id &&
                      provider.messages.isEmpty) {
                    _requestHistory();
                  }
                });
              }

              return Stack(
                children: [
                  Positioned.fill(
                    child: RefreshIndicator(
                      onRefresh: () => chatProvider.requestHistory(force: true),
                      color: color,
                      backgroundColor: isDark
                          ? AppConstants.darkCard
                          : Colors.white,
                      child: msgs.isEmpty && !thinking && !hasReasoning
                          ? ListView(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.55,
                                  child: _buildEmptyState(
                                    isDark,
                                    profile,
                                    isLoadingHistory,
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              reverse: true,
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount:
                                  msgs.length + ((thinking || hasReasoning) ? 1 : 0),
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
                                final hasThinkingItem = thinking || hasReasoning;
                                final msgOffset = hasThinkingItem ? index - 1 : index;
                                final msgIndex = msgs.length - 1 - msgOffset;
                                final msg = msgs[msgIndex];

                                // Show retry on user messages where agent didn't respond:
                                // - message marked as failed (send failure)
                                // - newest message and not thinking (agent finished but no reply)
                                // - next message is also user (agent skipped this one)
                                final needsRetry =
                                    msg.isUser &&
                                    (chatProvider.isMessageFailed(msg.id) ||
                                     (msgIndex == msgs.length - 1 && !thinking) ||
                                        (msgIndex < msgs.length - 1 &&
                                            msgs[msgIndex + 1].isUser));
                                final isFailed = chatProvider.isMessageFailed(msg.id);
                                return ChatBubble(
                                  message: msg,
                                  profileName: profile.name,
                                  isReplyTarget: chatProvider.replyTarget?.id == msg.id,
                                  onReply: () => chatProvider.setReplyTarget(msg),
                                  showRetry: needsRetry,
                                  isFailed: isFailed,
                                  onRetry: needsRetry
                                      ? () => _retryMessage(msg.id, msg.content)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ),
                  if (widget.showHeader)
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildOverlayActionButton(
                          isDark: isDark,
                          icon: isLoadingHistory
                              ? CupertinoIcons.refresh
                              : CupertinoIcons.add,
                          onTap: isLoadingHistory
                              ? () {}
                              : () => _requestHistory(force: true),
                          tooltip: 'Load conversation history',
                        ),
                      ),
                    ),
                  if (_showScrollToBottom && msgs.isNotEmpty)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _buildOverlayActionButton(
                        isDark: isDark,
                        icon: CupertinoIcons.chevron_down,
                        onTap: () => _scrollToBottom(force: true),
                        tooltip: 'Scroll to latest',
                      ),
                    ),
                ],
              );
            },
            ), // ChatProvider consumer
          ), // Container background
        ), // Expanded

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
                  Icon(CupertinoIcons.arrowshape_turn_up_left, size: 16, color: color),
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
                    child: Icon(CupertinoIcons.clear, size: 16, color: color),
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
                  MouseRegion(
                    onEnter: (_) {
                      if (isThinking) setState(() => _hoveringStop = true);
                    },
                    onExit: (_) {
                      if (isThinking) setState(() => _hoveringStop = false);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: (isThinking && _hoveringStop)
                            ? const Color(0xFFE81123)
                            : (isThinking ? Colors.grey : color),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        iconSize: 20,
                        icon: (isThinking && _hoveringStop)
                            ? const Icon(CupertinoIcons.stop, color: Colors.white)
                            : isThinking
                                ? const Icon(CupertinoIcons.time, color: Colors.white)
                                : const Icon(CupertinoIcons.paperplane, color: Colors.white),
                        onPressed: isThinking ? _confirmCancel : _sendMessage,
                      ),
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
