import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fuzzy/fuzzy.dart';
import '../models/agent_profile.dart';

/// Result returned when the user selects a profile or cancels.
class QuickPanelResult {
  final AgentProfile? selected;
  const QuickPanelResult({this.selected});
}

/// A Ctrl+P / Ctrl+R quick panel that overlays the current screen,
/// lets the user search profile names via fuzzy matching,
/// navigate with arrow keys, and select with Enter.
class ProfileQuickPanel extends StatefulWidget {
  final List<AgentProfile> profiles;
  final String activeProfileId;

  const ProfileQuickPanel({
    super.key,
    required this.profiles,
    this.activeProfileId = '',
  });

  /// Show the quick panel as a dialog, returning the selected profile.
  static Future<AgentProfile?> show(
    BuildContext context, {
    required List<AgentProfile> profiles,
    String activeProfileId = '',
  }) async {
    final result = await showDialog<QuickPanelResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (_) => ProfileQuickPanel(
        profiles: profiles,
        activeProfileId: activeProfileId,
      ),
    );
    return result?.selected;
  }

  @override
  State<ProfileQuickPanel> createState() => _ProfileQuickPanelState();
}

class _ProfileQuickPanelState extends State<ProfileQuickPanel> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late List<_Entry> _entries;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _entries = widget.profiles
        .map((p) => _Entry(profile: p, titleMatches: const []))
        .toList();
    _selectedIndex = _entries.isNotEmpty ? 0 : -1;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateFilter(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _entries = widget.profiles
            .map((p) => _Entry(profile: p, titleMatches: const []))
            .toList();
        _selectedIndex = _entries.isNotEmpty ? 0 : -1;
      });
      return;
    }

    final fuzzy = Fuzzy<AgentProfile>(
      widget.profiles,
      options: FuzzyOptions<AgentProfile>(
        threshold: 0.4,
        tokenize: false,
        matchAllTokens: false,
        minTokenCharLength: 1,
        shouldNormalize: true,
        keys: [
          WeightedKey<AgentProfile>(
            name: 'name',
            getter: (p) => p.name,
            weight: 3,
          ),
          WeightedKey<AgentProfile>(
            name: 'id',
            getter: (p) => p.id,
            weight: 2,
          ),
          WeightedKey<AgentProfile>(
            name: 'emoji',
            getter: (p) => p.emoji,
            weight: 1,
          ),
        ],
      ),
    );

    final results = fuzzy.search(query);
    final entries = results.map((r) {
      final matches = r.matches
          .where((m) => m.key == 'name')
          .expand((m) => m.matchedIndices)
          .map((i) => _MatchRange(start: i.start, end: i.end))
          .toList();
      return _Entry(
        profile: r.item,
        titleMatches: _mergeRanges(matches),
      );
    }).toList();

    setState(() {
      _entries = entries;
      _selectedIndex = entries.isNotEmpty ? 0 : -1;
    });
  }

  List<_MatchRange> _mergeRanges(List<_MatchRange> ranges) {
    if (ranges.isEmpty) return const [];
    final sorted = List<_MatchRange>.from(ranges)
      ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <_MatchRange>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      final last = merged.last;
      final cur = sorted[i];
      if (cur.start <= last.end + 1) {
        merged[merged.length - 1] =
            _MatchRange(start: last.start, end: last.end > cur.end ? last.end : cur.end);
      } else {
        merged.add(cur);
      }
    }
    return merged;
  }

  void _move(int delta) {
    if (_entries.isEmpty) return;
    setState(() {
      final len = _entries.length;
      _selectedIndex = (_selectedIndex + delta) % len;
      if (_selectedIndex < 0) _selectedIndex += len;
    });
  }

  void _activate() {
    if (_selectedIndex < 0 || _selectedIndex >= _entries.length) {
      Navigator.of(context).pop(QuickPanelResult());
      return;
    }
    final profile = _entries[_selectedIndex].profile;
    Navigator.of(context).pop(QuickPanelResult(selected: profile));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _move((_entries.length ~/ 4).clamp(1, 10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _move(-(_entries.length ~/ 4).clamp(1, 10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(QuickPanelResult());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2937) : Colors.white;
    final divider = theme.dividerColor;
    final highlightBg = isDark
        ? const Color(0xFF2563EB).withValues(alpha: 0.28)
        : const Color(0xFFDDE9FF);
    final activeHighlight = isDark
        ? const Color(0xFF2563EB).withValues(alpha: 0.40)
        : const Color(0xFFB3D4FF);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 480,
            minWidth: 360,
            maxHeight: 480,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: divider),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 20,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search field
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search profiles…',
                    prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF2563EB)),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF111827)
                        : const Color(0xFFF3F4F6),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                    isDense: true,
                  ),
                  onChanged: _updateFilter,
                  onSubmitted: (_) => _activate(),
                ),
              ),
              Divider(height: 1, thickness: 1, color: divider),
              // Results list
              Flexible(
                child: _entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No profiles found',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _entries.length,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemBuilder: (_, index) {
                          final entry = _entries[index];
                          final profile = entry.profile;
                          final isSelected = index == _selectedIndex;
                          final isActive =
                              profile.id == widget.activeProfileId;
                          return InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            onTap: () {
                              setState(() => _selectedIndex = index);
                              _activate();
                            },
                            child: Container(
                              color: isSelected
                                  ? (isActive
                                      ? activeHighlight
                                      : highlightBg)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  // Emoji + status dot
                                  Stack(
                                    children: [
                                      Text(profile.emoji,
                                          style: const TextStyle(
                                              fontSize: 20)),
                                      if (profile.online)
                                        Positioned(
                                          right: -2,
                                          bottom: -2,
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color:
                                                  const Color(0xFF22C55E),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: bg,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  // Name + description
                                  Expanded(
                                    child: _buildTitle(
                                      profile.name,
                                      entry.titleMatches,
                                      theme.textTheme.bodyMedium,
                                      isSelected,
                                    ),
                                  ),
                                  // Active indicator
                                  if (isActive)
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF2563EB)
                                                .withValues(alpha: 0.3)
                                            : const Color(0xFF2563EB)
                                                .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'active',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? const Color(0xFF93C5FD)
                                              : const Color(0xFF2563EB),
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
              // Footer hint
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: divider)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_entries.length} profile${_entries.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    Text(
                        '↑↓ navigate  ↵ open  esc close',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white30 : Colors.black45,
                        ),
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

  Widget _buildTitle(
    String title,
    List<_MatchRange> matches,
    TextStyle? baseStyle,
    bool isSelected,
  ) {
    final resolved = (baseStyle ?? const TextStyle()).copyWith(
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      fontSize: 14,
    );

    if (title.isEmpty || matches.isEmpty) {
      return Text(title, style: resolved, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    const highlight = Colors.deepOrange;
    final highlightStyle = resolved.copyWith(color: highlight);
    final spans = <TextSpan>[];
    var cur = 0;
    for (final r in matches) {
      final start = r.start.clamp(0, title.length);
      final end = (r.end + 1).clamp(0, title.length);
      if (end <= cur) continue;
      final rs = start > cur ? start : cur;
      if (rs > cur) spans.add(TextSpan(text: title.substring(cur, rs)));
      spans.add(TextSpan(text: title.substring(rs, end), style: highlightStyle));
      cur = end;
    }
    if (cur < title.length) spans.add(TextSpan(text: title.substring(cur)));

    return Text.rich(
      TextSpan(children: spans, style: resolved),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Entry {
  final AgentProfile profile;
  final List<_MatchRange> titleMatches;
  const _Entry({required this.profile, required this.titleMatches});
}

class _MatchRange {
  final int start;
  final int end;
  const _MatchRange({required this.start, required this.end});
}
