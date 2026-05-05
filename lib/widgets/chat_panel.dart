import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posh_voice_input/posh_voice_input.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/font_settings_provider.dart';
import 'chat_bubble.dart';
import 'thinking_indicator.dart';
import 'toast.dart';
import 'win11_dialog.dart';

/// Reusable chat panel — the core chat UI without Scaffold/AppBar.
/// Used in the landscape sidebar layout or embedded in ChatScreen.
///
/// Uses [ListView.builder] with `reverse: true` so messages grow from the
/// bottom naturally — no need for scrollToBottom hacks.
class ChatPanel extends StatefulWidget {
  final AgentProfile profile;
  final bool showHeader;

  /// When non-zero, triggers auto-search in the panel.
  /// Paired with [searchQuery] — the text to search for.
  /// Increment this value each time a new search should be triggered
  /// (e.g., from the sidebar history-match tap).
  final int searchTriggerKey;
  final String searchQuery;

  const ChatPanel({
    super.key,
    required this.profile,
    this.showHeader = true,
    this.searchTriggerKey = 0,
    this.searchQuery = '',
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  late ChatProvider _chatProvider;
  bool _autoScroll = true;
  bool _initialScrollDone = false;
  bool _showScrollToBottom = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _isSearching = false;
  String _searchQuery = '';
  final List<_SearchResult> _searchResults = [];
  Timer? _searchDebounce;
  int _lastProcessedSearchKey = 0;

  /// Message ID that should flash (from search result tap).
  String? _flashingMessageId;

  /// Per-message GlobalKeys for precise scroll positioning.
  /// Keyed by message ID, used in [_scrollToMessage] to find exact RenderBox offset.
  final Map<String, GlobalKey> _messageKeys = {};

  // Input history for Up/Down arrow navigation
  int _historyIndex = -1; // -1 = current text, 0 = oldest, N-1 = newest
  String _currentDraft = ''; // saved current input when navigating history
  List<String> _inputHistory = [];

  // Voice input
  final PoshVoiceInputService _voiceService = PoshVoiceInputService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _switchToProfile(widget.profile.id);
      _restoreDraft();
    });
    _scrollController.addListener(_onScroll);
    _inputFocus.onKeyEvent = _onKeyEvent;
    _searchFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _toggleSearch();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _voiceService.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = context.read<ChatProvider>();
  }

  void _restoreDraft() {
    final draft = _chatProvider.getDraft(widget.profile.id);
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
      _chatProvider.saveDraft(oldWidget.profile.id, _inputController.text);
      _initialScrollDone = false;
      _autoScroll = true;
      _showScrollToBottom = false;
      _inputController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _switchToProfile(widget.profile.id);
        _restoreDraft();
        _inputFocus.requestFocus();
      });
    }
    // Handle external search trigger (from sidebar history-match tap)
    if (widget.searchTriggerKey != _lastProcessedSearchKey &&
        widget.searchQuery.isNotEmpty) {
      _lastProcessedSearchKey = widget.searchTriggerKey;
      final q = widget.searchQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_isSearching) {
          setState(() => _isSearching = true);
        }
        _searchController.text = q;
        _searchQuery = q;
        _searchDebounce?.cancel();
        _performSearch(q);
      });
    }
  }

  @override
  void dispose() {
    _saveDraft();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  void _saveDraft() {
    _chatProvider.saveDraft(widget.profile.id, _inputController.text);
  }

  void _switchToProfile(String profileId) {
    _chatProvider.switchProfile(profileId);
    _requestHistory();
    _inputHistory = List<String>.from(_chatProvider.inputHistoryForProfile(profileId));
    _historyIndex = -1;
    _currentDraft = '';
    // reverse:true — ListView naturally starts at bottom, no scroll needed
  }

  void _requestHistory({bool force = false}) {
    unawaited(_chatProvider.requestHistory(force: force));
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

  void _toggleSearch() {
    if (_isSearching) {
      _searchController.clear();
      _searchDebounce?.cancel();
      setState(() {
        _isSearching = false;
        _searchQuery = '';
        _searchResults.clear();
      });
    } else {
      setState(() { _isSearching = true; });
    }
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    final query = text.trim().toLowerCase();
    if (query == _searchQuery) return;
    _searchQuery = query;
    _searchDebounce = Timer(const Duration(milliseconds: 100), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) {
    final results = <_SearchResult>[];
    if (query.isNotEmpty) {
      final msgs = context.read<ChatProvider>().messages;
      for (int i = 0; i < msgs.length; i++) {
        if (msgs[i].content.toLowerCase().contains(query)) {
          results.add(_SearchResult(originalIndex: i, message: msgs[i]));
        }
      }
    }
    if (mounted) {
      setState(() {
        _searchResults
          ..clear()
          ..addAll(results);
      });
    }
  }

  void _scrollToMessage(int originalIndex) {
    final msgs = context.read<ChatProvider>().messages;
    if (msgs.isEmpty || originalIndex >= msgs.length) return;
    final targetMsg = msgs[originalIndex];
    final targetId = targetMsg.id;

    // Clear first so re-clicking same message re-triggers flash
    setState(() => _flashingMessageId = null);
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    const desiredFraction = 0.35; // target top edge at 35% from top of viewport

    // Phase 1 — rough index-based scroll to get target into viewport
    final ratio = originalIndex / (msgs.length - 1).clamp(1, msgs.length);
    final roughOffset = _scrollController.position.maxScrollExtent * (1.0 - ratio);
    // Add extra offset so the target is roughly in the upper half
    final roughAdjusted = (roughOffset + viewportHeight * desiredFraction)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      roughAdjusted,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    ).then((_) {
      if (!mounted || !_scrollController.hasClients) return;

      // Phase 2 — get exact RenderBox position and correct
      final key = _messageKeys[targetId];
      if (key?.currentContext == null) {
        // Fallback: target not rendered (shouldn't happen after phase 1)
        if (mounted) setState(() => _flashingMessageId = targetId);
        return;
      }

      // Find scroll view's RenderBox for coordinate reference
      final scrollContext = _scrollController.position.context.notificationContext;
      if (scrollContext == null) {
        if (mounted) setState(() => _flashingMessageId = targetId);
        return;
      }

      final targetRenderBox =
          key!.currentContext!.findRenderObject() as RenderBox;
      // ignore: use_build_context_synchronously — captured in same .then() callback, no await between
      final scrollRenderBox = scrollContext.findRenderObject() as RenderBox;

      // Get the target's top edge position relative to scroll view's top-left
      final targetViewportOffset =
          targetRenderBox.localToGlobal(
            Offset.zero,
            ancestor: scrollRenderBox,
          );
      final targetY = targetViewportOffset.dy; // physical Y in viewport coords

      // Desired physical position for target's top edge
      final desiredY = viewportHeight * desiredFraction;

      // Delta: in a reverse ListView, increasing pixels moves content UP.
      // If targetY > desiredY, target is too low → scroll down (increase pixels).
      final delta = targetY - desiredY;

      final correctedPixels = (_scrollController.position.pixels + delta)
          .clamp(0.0, _scrollController.position.maxScrollExtent);

      _scrollController.animateTo(
        correctedPixels,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ).then((_) {
        if (mounted) {
          setState(() => _flashingMessageId = targetId);
        }
      });
    });
    showToast(context, '已定位到第 ${originalIndex + 1} 条');
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
      showToast(context, '正在等待回复，请稍等');
      return;
    }

    var text = _inputController.text.trim();
    if (prepend != null && text.isNotEmpty) {
      text = '$prepend $text';
    }
    if (text.isEmpty) return;
    chatProvider.sendMessage(text);
    chatProvider.clearReplyTarget();
    chatProvider.saveDraft(widget.profile.id, '');
    _inputController.clear();
    // Push to input history
    chatProvider.pushToInputHistory(widget.profile.id, text);
    _inputHistory.add(text);
    if (_inputHistory.length > 10) {
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
    final inputText = _inputController.text.trim();
    final choice = await Win11Dialog.showThreeButton(
      context,
      title: 'AI 正在回复中',
      content: inputText.isNotEmpty
          ? '当前 agent 正在回复。要将您输入的内容稍后发送吗？'
          : '当前 agent 正在回复。要立即中止这次回答吗？',
      confirmText: '中止回答',
      cancelText: '继续等待',
      thirdText: '稍后发送',
      accentColor: const Color(0xFFE81123), // Win11 red accent
      icon: const Icon(CupertinoIcons.clear_circled,
          size: 32, color: Color(0xFFE81123)),
    );

    if (!mounted) return;
    final chatProvider = context.read<ChatProvider>();

    switch (choice) {
      case 1: // 中止回答
        chatProvider.cancelActiveResponse();
        break;
      case 2: // 稍后发送 — just queue, don't interrupt agent
        if (inputText.isNotEmpty) {
          chatProvider.enqueueMessage(_inputController.text);
          chatProvider.saveDraft(widget.profile.id, '');
          _inputController.clear();
          showToast(context, '已加入发送队列（${chatProvider.pendingCount}条）');
        }
        break;
      // case 0 (继续等待): do nothing
    }
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

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _isSearching) {
          _toggleSearch();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
      children: [
        // Search header bar — replaces profile header when searching
        if (widget.showHeader && _isSearching)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _searchQuery.isNotEmpty
                  ? Color.lerp(
                      isDark ? AppConstants.darkSurface : Colors.white,
                      Colors.yellow.shade400,
                      0.25,
                    )!
                  : isDark
                      ? AppConstants.darkSurface
                      : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(CupertinoIcons.arrow_left, size: 20,
                      color: isDark ? Colors.white70 : Colors.black54),
                  onPressed: _toggleSearch,
                  tooltip: 'Close search',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _onSearchChanged,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '搜索所有消息...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                    onTap: () {
                      _searchController.clear();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(CupertinoIcons.clear_circled_solid, size: 18,
                          color: isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                  ),
              ],
            ),
          ),

        // Profile header bar
        if (widget.showHeader && !_isSearching)
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
              const Spacer(),
              GestureDetector(
                onTap: _toggleSearch,
                child: Tooltip(
                  message: '搜索消息',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(CupertinoIcons.search, size: 16,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),

        // Search results overlay — scrollable list of matches
        if (_isSearching && _searchQuery.isNotEmpty && _searchResults.isNotEmpty)
          Container(
            constraints: BoxConstraints(
              maxHeight: 5 * 44.0, // 5 rows at ~44px each
            ),
            color: isDark ? AppConstants.darkSurface : Colors.white,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final result = _searchResults[index];
                final roleLabel = result.message.isUser ? '你' : 'AI';
                final snippet = result.message.content;
                // Find the match position for highlighting
                final lower = snippet.toLowerCase();
                final matchIdx = lower.indexOf(_searchQuery);
                final preview = snippet.length > 80
                    ? '...${snippet.substring(matchIdx - 20 < 0 ? 0 : matchIdx - 20, (matchIdx + _searchQuery.length + 40).clamp(0, snippet.length))}...'
                    : snippet;
                return Container(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      isDark ? AppConstants.darkSurface : Colors.white,
                      Colors.yellow.shade400,
                      0.08,
                    )!,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white10 : Colors.black12,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        _scrollToMessage(result.originalIndex);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: result.message.isUser
                                  ? AppConstants.primaryBlue.withValues(alpha: 0.2)
                                  : color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: result.message.isUser
                                    ? AppConstants.primaryBlue
                                    : color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _HighlightedText(
                              text: preview,
                              query: _searchQuery,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              highlightStyle: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.amber.shade200 : Colors.orange.shade800,
                                backgroundColor: isDark
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
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
                                  msgs.length + ((thinking || hasReasoning) ? 1 : 0) + (widget.showHeader ? 1 : 0),
                              itemBuilder: (context, index) {
                                // Last item in reverse mode = top of list = history button
                                final hasHistoryButton = widget.showHeader;
                                final totalItems = msgs.length + ((thinking || hasReasoning) ? 1 : 0) + (hasHistoryButton ? 1 : 0);
                                if (hasHistoryButton && index == totalItems - 1) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                                  );
                                }
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
                                  key: _messageKeys.putIfAbsent(
                                    msg.id,
                                    () => GlobalKey(),
                                  ),
                                  message: msg,
                                  profileName: profile.name,
                                  flashMessageId: _flashingMessageId,
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
                  // Load history button — always visible above the first message
                  if (widget.showHeader && msgs.isEmpty)
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

        // Reply banner — top area shows quoted message with gray left bar + darker bg
        Consumer<ChatProvider>(
          builder: (context, chatProvider, _) {
            final target = chatProvider.replyTarget;
            if (target == null) return const SizedBox.shrink();
            final isAgent = target.isAgent;
            return Container(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 8px gray left border
                  Container(
                    width: 3,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isAgent
                                  ? CupertinoIcons.person
                                  : CupertinoIcons.person_alt_circle,
                              size: 12,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isAgent ? 'Agent' : 'You',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          target.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => chatProvider.clearReplyTarget(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(CupertinoIcons.clear_circled_solid,
                          size: 18,
                          color: isDark ? Colors.white38 : Colors.black38),
                    ),
                  ),
                ),
                ],
              ),
            );
          },
        ),

        // Pending queue display
        Consumer<ChatProvider>(
          builder: (context, chatProvider, _) {
            if (!chatProvider.hasPendingMessages) return const SizedBox.shrink();
            return Container(
              color: isDark
                  ? AppConstants.darkSurface
                  : Colors.white,
              padding: const EdgeInsets.only(left: 16, right: 12, top: 5, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(CupertinoIcons.clock, size: 12,
                          color: isDark ? Colors.white54 : Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        '发送队列（${chatProvider.pendingCount}条）',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                  for (final entry in chatProvider.pendingQueue.asMap().entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              final removed = chatProvider
                                  .removeFromPendingQueue(entry.key);
                              if (removed.isNotEmpty) {
                                final pid = widget.profile.id;
                                chatProvider
                                    .pushToInputHistory(pid, removed);
                                _inputHistory.add(removed);
                                if (_inputHistory.length > 10) {
                                  _inputHistory.removeAt(0);
                                }
                              }
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Padding(
                              padding:
                                  const EdgeInsets.only(right: 6, top: 2),
                              child: Icon(
                                CupertinoIcons.clear_circled_solid,
                                size: 14,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.black38,
                              ),
                            ),
                          ),
                          ),
                          Expanded(
                            child: Text(
                              entry.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 3),
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
                        suffixIcon: context.read<FontSettingsProvider>().voicesEnabled
                            ? PoshVoiceInputWidget(
                                service: _voiceService,
                                isDark: isDark,
                                onResult: (text) {
                                  final current = _inputController.text;
                                  _inputController.text = current.isEmpty
                                      ? text
                                      : '$current${current.endsWith(' ') ? '' : ' '}$text';
                                  _inputController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _inputController.text.length),
                                  );
                                },
                                onError: (err) {
                                  showToast(context, err);
                                },
                              )
                            : null,
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
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isThinking
                            ? const Color(0xFFE81123)
                            : color,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        iconSize: 20,
                        icon: isThinking
                            ? const Icon(CupertinoIcons.stop, color: Colors.white)
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
    ), // Column
  ); // Focus
  }
}

/// A search result match — holds the original message index and the message.
class _SearchResult {
  final int originalIndex;
  final ChatMessage message;
  const _SearchResult({required this.originalIndex, required this.message});
}

/// A text widget that highlights occurrences of [query] within [text].
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final TextStyle highlightStyle;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    required this.highlightStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis);

    final lower = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lower.indexOf(lowerQuery, start);
      if (idx < 0) break;
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: highlightStyle,
      ));
      start = idx + query.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(children: spans, style: style),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
