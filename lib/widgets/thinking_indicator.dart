import 'dart:async';
import 'package:flutter/material.dart';
import '../config/constants.dart';

/// Animated thinking indicator that cycles dots and shows reasoning text.
class ThinkingIndicator extends StatefulWidget {
  final String emoji;
  final String reasoning;
  final bool isActive;

  const ThinkingIndicator({
    super.key,
    this.emoji = '🤖',
    this.reasoning = '',
    this.isActive = true,
  });

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  static const _frames = ['  ', '. ', '..', '...'];
  int _frame = 0;
  Timer? _timer;
  double _cachedBubbleMaxWidth = 0;
  Timer? _resizeDebounce;
  final ScrollController _reasoningScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() => _frame = (_frame + 1) % _frames.length);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollReasoningToBottom());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resizeDebounce?.cancel();
    _reasoningScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ThinkingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reasoning != widget.reasoning ||
        oldWidget.isActive != widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollReasoningToBottom(),
      );
    }
  }

  void _scrollReasoningToBottom() {
    if (!mounted || !_reasoningScrollController.hasClients) {
      return;
    }

    final position = _reasoningScrollController.position;
    _reasoningScrollController.jumpTo(position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reasoning = widget.reasoning.trim();
    final hasReasoning = reasoning.isNotEmpty;
    final statusLabel = widget.isActive ? 'Thinking' : 'Thought process';
    final reasoningText = hasReasoning
        ? reasoning
        : 'Waiting for reasoning updates...';
    const reasoningFontSize = 12.0;
    const reasoningLineHeight = 1.35;
    const reasoningVisibleLines = 3;
    final reasoningHeight =
        reasoningFontSize * reasoningLineHeight * reasoningVisibleLines;
    final gradient = const LinearGradient(
      colors: [Color(0xFFC0C0C0), Color(0xFF808080)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? AppConstants.darkCard : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(widget.emoji, style: const TextStyle(fontSize: 14)),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final newWidth = constraints.maxWidth * 0.80;
                  if (newWidth != _cachedBubbleMaxWidth) {
                    _resizeDebounce?.cancel();
                    _resizeDebounce = Timer(const Duration(milliseconds: 100), () {
                      if (mounted) setState(() => _cachedBubbleMaxWidth = newWidth);
                    });
                  }
                  final bubbleMaxWidth = _cachedBubbleMaxWidth > 0 ? _cachedBubbleMaxWidth : newWidth;
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                    child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppConstants.darkCard : Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _frames[_frame],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black54,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.06),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: reasoningHeight),
                          child: ScrollConfiguration(
                            behavior: const MaterialScrollBehavior().copyWith(
                              scrollbars: false,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  controller: _reasoningScrollController,
                                  physics: const BouncingScrollPhysics(),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: constraints.maxWidth,
                                          child: ShaderMask(
                                            blendMode: BlendMode.srcIn,
                                            shaderCallback: (bounds) => gradient.createShader(
                                              Rect.fromLTWH(
                                                0,
                                                0,
                                                constraints.maxWidth,
                                                bounds.height,
                                              ),
                                            ),
                                            child: Text(
                                              reasoningText,
                                              softWrap: true,
                                              style: const TextStyle(
                                                fontSize: reasoningFontSize,
                                                fontStyle: FontStyle.italic,
                                                height: reasoningLineHeight,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  ),
);
}
}