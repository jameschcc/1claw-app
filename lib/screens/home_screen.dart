import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/chat_provider.dart';
import '../providers/profiles_provider.dart';
import '../services/api_service.dart';
import '../services/server_config_store.dart';
import '../widgets/agent_card.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/chat_panel.dart';
import '../widgets/user_list_item.dart';
import '../widgets/toast.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _dialogShown = false;
  late bool _isWide;
  Timer? _resizeTimer;
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';
  String _sortBy = 'time'; // 'time' or 'alpha'
  int _searchTriggerKey = 0;
  late AnimationController _refreshSpinCtrl;
  late AnimationController _gearSpinCtrl;
  final Map<String, bool> _hoverStates = {};
  final FocusNode _filterFocus = FocusNode();
  bool _filterHasFocus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dialogShown = false;
    _refreshSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() => setState(() {}));
    _gearSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() => setState(() {}));
    _filterFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _filterController.clear();
        setState(() => _filterQuery = '');
        _filterFocus.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _filterFocus.addListener(() {
      if (mounted) setState(() => _filterHasFocus = _filterFocus.hasFocus);
    });
    // Default to portrait; corrected on first post-frame
    _isWide = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _isWide = MediaQuery.of(context).size.width >= 600;
    });
  }

  /// Navigate to settings with a popup animation that originates
  /// from where the gear icon is (bottom-left in landscape, top-right in portrait).
  void _openSettings(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder:
          (context, animation, secondaryAnimation) => const SettingsScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final alignment =
            _isWide ? Alignment.bottomLeft : Alignment.topRight;
        return ScaleTransition(
          alignment: alignment,
          scale: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
          child: FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resizeTimer?.cancel();
    _refreshSpinCtrl.dispose();
    _gearSpinCtrl.dispose();
    _filterController.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset dialog flag when widget is new
    _dialogShown = false;
  }

  @override
  void didChangeMetrics() {
    // Window resize events arrive at ~60 fps. Debounce the layout switch
    // so the entire widget tree only rebuilds after resize settles.
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      final width = MediaQuery.of(context).size.width;
      final expected = width >= 600;
      if (expected != _isWide) {
        setState(() => _isWide = expected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT: Do NOT call MediaQuery.of(context) here. Using cached
    // _isWide avoids registering a MediaQuery dependency, which means
    // window resize events do NOT trigger a rebuild cascade through
    // the entire widget tree. Only didChangeMetrics → debounce → setState
    // triggers layout switches after resize settles.

    // Check for manual reconnect dialog once per flag
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ProfilesProvider>();
      if (provider.needsManualReconnect && !_dialogShown) {
        _dialogShown = true;
        _showReconnectDialog(context, provider);
      }
    });

    return _isWide ? _buildLandscapeLayout() : _buildPortraitLayout();
  }

  void _showReconnectDialog(BuildContext context, ProfilesProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(CupertinoIcons.wifi_slash, size: 24),
            SizedBox(width: 8),
            Text('Reconnect Required'),
          ],
        ),
        content: const Text(
          'Auto-reconnect has stopped after multiple attempts.\n'
          'Tap the button below to try connecting again.',
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              provider.resetNeedsManualReconnect();
              _dialogShown = false;
            },
            icon: const Icon(CupertinoIcons.refresh),
            label: const Text('Reconnect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.onlineGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    ).then((_) {
      // When dialog is dismissed, allow it to re-show if still needed
      _dialogShown = false;
    });
  }

  // ─── Portrait Mode (existing grid layout) ──────────────────────

  Widget _buildPortraitLayout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('1Claw',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        centerTitle: false,
        actions: [
          Consumer<ProfilesProvider>(
            builder: (_, provider, _) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ConnectionIndicator(
                isConnected: provider.isConnected,
                onRetry: () => provider.reconnect(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.gear),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: Consumer<ProfilesProvider>(
        builder: (context, provider, _) {
          if (provider.profiles.isEmpty) {
            return _buildEmptyState(isDark);
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Row(
                    children: [
                      Text('Your Agents',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.white70 : Colors.black87)),
                      if (provider.hasPinned()) ...[
                        const SizedBox(width: 8),
                        const Icon(CupertinoIcons.star, size: 14, color: Colors.amber),
                        Text(
                          '${provider.pinnedProfiles.length}',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38),
                        ),
                      ],
                    ],
                  ),
                ),
                // Profiles area
                Expanded(
                  child: _buildProfilesArea(provider, isDark),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Landscape Mode (sidebar + chat panel) ─────────────────────

  Widget _buildLandscapeLayout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Consumer<ProfilesProvider>(
        builder: (context, provider, _) {
          final profiles = provider.profiles;

          if (profiles.isEmpty) {
            return _buildEmptyState(isDark);
          }

          // Ensure a profile is selected
          final activeId = provider.activeProfileId;
          if (activeId.isEmpty || !profiles.any((p) => p.id == activeId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              provider.setActiveProfile(profiles.first.id);
            });
          }

          final activeProfile = activeId.isNotEmpty
              ? profiles.firstWhere(
                  (p) => p.id == activeId,
                  orElse: () => profiles.first,
                )
              : profiles.first;

          return Row(
            children: [
// ── Toolbar (60px) — darker gray, gear at bottom ──
              _buildToolbar(isDark, provider),

              // ── Divider 1 ──
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? Colors.white12 : Colors.black12,
              ),

              // ── Left sidebar (240px) ──
              Container(
                width: 240,
                color: isDark ? const Color(0xFF282828) : const Color(0xFFF0F0F0),
                child: Column(
                  children: [
                    // Sidebar header (simplified — just the app title)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF282828) : const Color(0xFFF0F0F0),
                        border: Border(
                          bottom: BorderSide(
                            color: isDark ? Colors.white12 : Colors.black12,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: const Center(
                        child: Text('1Claw',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    // User list
                    Expanded(
                      child: () {
                        final sorted = _sortProfiles(profiles);
                        if (_filterQuery.isEmpty) {
                          // No filtering — show all as one flat list
                          return ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: sorted.length,
                            itemBuilder: (context, index) {
                              final profile = sorted[index];
                              return UserListItem(
                                profile: profile,
                                isSelected: profile.id == activeId,
                                onTap: () {
                                  provider.setActiveProfile(profile.id);
                                },
                                onTogglePin: () =>
                                    provider.togglePin(profile.id),
                              );
                            },
                          );
                        }
                        // Filtering: split into name matches and history matches
                        final q = _filterQuery.toLowerCase();
                        final nameMatches = <AgentProfile>[];
                        final historyMatches = <AgentProfile>[];
                        for (final p in sorted) {
                          if (p.name.toLowerCase().contains(q)) {
                            nameMatches.add(p);
                          } else if (_matchesAnyMessage(
                              context.read<ChatProvider>(), p.id, q)) {
                            historyMatches.add(p);
                          }
                        }
                        final hasHistory = historyMatches.isNotEmpty;
                        final total = nameMatches.length +
                            (hasHistory ? 1 + historyMatches.length : 0);
                        return ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: total,
                          itemBuilder: (context, index) {
                            // Section 1: name matches
                            if (index < nameMatches.length) {
                              final profile = nameMatches[index];
                              return UserListItem(
                                profile: profile,
                                isSelected: profile.id == activeId,
                                onTap: () {
                                  provider.setActiveProfile(profile.id);
                                },
                                onTogglePin: () =>
                                    provider.togglePin(profile.id),
                              );
                            }
                            // Section header
                            if (index == nameMatches.length) {
                              return _buildHistorySectionHeader(
                                  _filterQuery, isDark);
                            }
                            // Section 2: history matches
                            final hi = index - nameMatches.length - 1;
                            final profile = historyMatches[hi];
                            return UserListItem(
                              profile: profile,
                              isSelected: profile.id == activeId,
                              onTap: () {
                                provider.setActiveProfile(profile.id);
                                setState(() => _searchTriggerKey++);
                              },
                              onTogglePin: () =>
                                  provider.togglePin(profile.id),
                            );
                          },
                        );
                      }(),
                    ),
                    // ── Filter bar (only when >5 profiles) ──
                    if (profiles.length > 5)
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF282828) : const Color(0xFFF0F0F0),
                          border: Border(
                            top: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                CupertinoIcons.search,
                                size: 14,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _filterController,
                                focusNode: _filterFocus,
                                onChanged: (v) => setState(() => _filterQuery = v),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _filterQuery.isNotEmpty
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: _filterQuery.isNotEmpty
                                      ? Colors.yellow.shade400
                                      : Colors.transparent,
                                  hintText: 'Filter Agent',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white30 : Colors.black38,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            if (_filterQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _filterController.clear();
                                  setState(() => _filterQuery = '');
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    CupertinoIcons.clear_circled_solid,
                                    size: 16,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            // Sort by time
                            _sortBtn(
                              icon: CupertinoIcons.clock,
                              isActive: _sortBy == 'time',
                              isDark: isDark,
                              onTap: () => setState(() => _sortBy = 'time'),
                            ),
                            const SizedBox(width: 2),
                            // Sort by A-Z
                            _sortBtn(
                              icon: CupertinoIcons.textformat_abc,
                              isActive: _sortBy == 'alpha',
                              isDark: isDark,
                              onTap: () => setState(() => _sortBy = 'alpha'),
                            ),
                          ],
                        ),
                      ),
                    // Bottom bar: connection only (gear moved to toolbar)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF282828) : const Color(0xFFF0F0F0),
                        border: Border(
                          top: BorderSide(
                            color: isDark ? Colors.white12 : Colors.black12,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Consumer<ProfilesProvider>(
                          builder: (_, p, _) => ConnectionIndicator(
                            isConnected: p.isConnected,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Divider 2 ──
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? Colors.white12 : Colors.black12,
              ),

              // ── Right: chat panel ──
              Expanded(
                child: ChatPanel(
                  profile: activeProfile,
                  searchTriggerKey: _searchTriggerKey,
                  searchQuery: _filterQuery,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Portrait profile area: two-column or single group ────────

  Widget _buildProfilesArea(ProfilesProvider provider, bool isDark) {
    final pinned = provider.pinnedProfiles;
    final unpinned = provider.profiles.where((p) => !p.isPinned).toList();
    final hasBoth = pinned.isNotEmpty && unpinned.isNotEmpty;

    return hasBoth
        ? _buildTwoColumns(pinned, unpinned, provider, isDark)
        : _buildSingleGroup(provider, isDark);
  }

  /// Two-column layout: left = favorites (40%), right = others (60%, 2-column grid).
  /// Both card types are square.
  Widget _buildTwoColumns(
    List<AgentProfile> pinned,
    List<AgentProfile> unpinned,
    ProfilesProvider provider,
    bool isDark,
  ) {
    Widget _card(AgentProfile profile, {bool compact = false}) => AgentCard(
          profile: profile,
          isActive: profile.id == provider.activeProfileId,
          onTap: () {
            provider.setActiveProfile(profile.id);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(profile: profile)),
            );
          },
          onTogglePin: () => provider.togglePin(profile.id),
          compact: compact,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: favorites (40%, single column, square cards)
        Expanded(
          flex: 3,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final profile in pinned)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: _card(profile),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Divider between columns
        const SizedBox(width: 12),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: isDark ? Colors.white12 : Colors.black12,
          indent: 16,
          endIndent: 16,
        ),
        const SizedBox(width: 12),
        // Right: non-favorites (60%, 2-column grid, square cards)
        Expanded(
          flex: 5,
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 6.0;
                final cardWidth = (constraints.maxWidth - gap) / 2;
                return SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < unpinned.length; i += 2) ...[
                        if (i > 0) const SizedBox(height: gap),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Left card in pair
                            SizedBox(
                              width: cardWidth,
                              child: AspectRatio(
                                aspectRatio: 1.0,
                                child: _card(unpinned[i], compact: true),
                              ),
                            ),
                            const SizedBox(width: gap),
                            // Right card in pair (if exists)
                            if (i + 1 < unpinned.length)
                              SizedBox(
                                width: cardWidth,
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: _card(unpinned[i + 1], compact: true),
                                ),
                              )
                            else
                              SizedBox(width: cardWidth), // placeholder to keep left aligned
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Single group: standard grid when all profiles are the same type.
  Widget _buildSingleGroup(ProfilesProvider provider, bool isDark) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.9,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: provider.profiles.length,
      itemBuilder: (context, index) {
        final profile = provider.profiles[index];
        return AgentCard(
          profile: profile,
          isActive: profile.id == provider.activeProfileId,
          onTap: () {
            provider.setActiveProfile(profile.id);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(profile: profile)),
            );
          },
          onTogglePin: () => provider.togglePin(profile.id),
        );
      },
    );
  }

  // ─── Sidebar profile filter ────────────────────────────────────

  bool _matchesAnyMessage(ChatProvider chatProvider, String profileId, String query) {
    final messages = chatProvider.getMessagesForProfile(profileId);
    for (final m in messages) {
      if (m.content.toLowerCase().contains(query)) return true;
    }
    return false;
  }

  Widget _buildHistorySectionHeader(String query, bool isDark) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: Text(
        '历史聊天中包含"$query"的',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }

  void _showCreateProfileDialog(BuildContext context, ProfilesProvider provider) {
    final nameCtl = TextEditingController();
    String? inheritFrom;
    showDialog(
      context: context,
      builder: (ctx) {
        final profiles = provider.profiles.where((p) => !p.isSpawn).toList();
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(CupertinoIcons.person_badge_plus, size: 22),
                SizedBox(width: 8),
                Text('Create Profile'),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Name:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'e.g. dev-test',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Inherit from:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: inheritFrom,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'Select source profile',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    items: profiles.map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.emoji} ${p.name}', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => inheritFrom = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: nameCtl.text.trim().isNotEmpty
                    ? () {
                        final name = nameCtl.text.trim();
                        Navigator.of(context).pop();
                        _executeCreateProfile(name, inheritFrom, provider);
                      }
                    : null,
                icon: const Icon(CupertinoIcons.person_badge_plus, size: 16),
                label: const Text('Create'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _executeCreateProfile(String name, String? inheritFrom, ProfilesProvider provider) async {
    try {
      final cfg = await ServerConfigStore.load();
      final api = ApiService(baseUrl: cfg.apiUrl);
      await api.createNewProfile(name, inheritFrom: inheritFrom);
      // Trigger status refresh so the new profile appears
      provider.requestStatus();
      if (context.mounted) {
        showToast(context, 'Profile "$name" created successfully');
      }
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'Failed: $e');
      }
    }
  }

  void _showSpawnDialog(BuildContext context, ProfilesProvider provider) {
    final profiles = provider.profiles.where((p) => !p.isSpawn).toList();
    if (profiles.isEmpty) {
      showToast(context, 'No profiles to spawn');
      return;
    }
    String? selectedId = profiles.length == 1 ? profiles.first.id : null;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(CupertinoIcons.doc_on_doc, size: 22),
              SizedBox(width: 8),
              Text('Spawn Duplicate'),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This creates a new agent process running the same profile, without duplicating files on disk.',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
                const Text('Choose profile:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    hintText: 'Select profile',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: profiles.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.emoji} ${p.name}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: selectedId != null
                  ? () {
                      final id = selectedId!;
                      Navigator.of(context).pop();
                      _executeSpawn(id, provider);
                    }
                  : null,
              icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
              label: const Text('Spawn'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSpawn(String profileId, ProfilesProvider provider) async {
    try {
      final cfg = await ServerConfigStore.load();
      final api = ApiService(baseUrl: cfg.apiUrl);
      final result = await api.spawnProfile(profileId);
      // Trigger status refresh so the spawned profile appears
      provider.requestStatus();
      if (context.mounted) {
        final name = result['name'] ?? result['profile_id'] ?? profileId;
        showToast(context, 'Spawned "$name" from "$profileId"');
      }
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'Failed: $e');
      }
    }
  }

  // ─── Toolbar helpers with hover effects ──────────────────────

  Widget _buildToolbar(bool isDark, ProfilesProvider provider) {
    return Container(
      width: 60,
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFD8D8D8),
      child: Column(
        children: [
          const Spacer(),
          _toolbarBtn(
            key: 'create',
            icon: const Icon(CupertinoIcons.person_badge_plus, size: 22),
            isDark: isDark,
            onTap: provider.isConnected
                ? () => _showCreateProfileDialog(context, provider)
                : null,
          ),
          const SizedBox(height: 4),
          _toolbarBtn(
            key: 'spawn',
            icon: const Icon(CupertinoIcons.doc_on_doc, size: 22),
            isDark: isDark,
            onTap: provider.isConnected
                ? () => _showSpawnDialog(context, provider)
                : null,
          ),
          const SizedBox(height: 4),
          _toolbarBtn(
            key: 'refresh',
            icon: const Icon(CupertinoIcons.refresh, size: 22),
            isDark: isDark,
            spinController: _refreshSpinCtrl,
            onTap: () {
              if (!provider.isConnected) {
                provider.reconnect();
              }
              _refreshSpinCtrl.forward(from: 0);
              provider.requestStatus();
            },
          ),
          const SizedBox(height: 4),
          _toolbarBtn(
            key: 'settings',
            icon: const Icon(CupertinoIcons.gear, size: 22),
            isDark: isDark,
            spinController: _gearSpinCtrl,
            onTap: () {
              _gearSpinCtrl.forward(from: 0);
              _openSettings(context);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _toolbarBtn({
    required String key,
    required Widget icon,
    required bool isDark,
    required VoidCallback? onTap,
    AnimationController? spinController,
  }) {
    final isHovered = _hoverStates[key] ?? false;

    Widget btn = Opacity(
      opacity: 0.9,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isHovered
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Center(child: icon),
        ),
      ),
    );

    if (spinController != null) {
      btn = RotationTransition(turns: spinController, child: btn);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hoverStates[key] = true),
      onExit: (_) => setState(() => _hoverStates[key] = false),
      child: btn,
    );
  }

  Widget _sortBtn({
    required IconData icon,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final key = 'sort_${isActive ? _sortBy : ''}_$icon';
    final isHovered = _hoverStates[key] ?? false;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoverStates[key] = true),
      onExit: (_) => setState(() => _hoverStates[key] = false),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isHovered || isActive
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isActive
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white38 : Colors.black38),
          ),
        ),
      ),
    );
  }

  /// Sort profiles by server order (most recent first) or alphabetically.
  List<AgentProfile> _sortProfiles(List<AgentProfile> profiles) {
    if (_sortBy == 'alpha') {
      final sorted = List<AgentProfile>.from(profiles);
      sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return sorted;
    }
    // Time sort: return as-is (server delivers in connection/activity order)
    return profiles;
  }

  // ─── Shared widgets ────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🤖', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('No agents connected',
              style: TextStyle(
                  fontSize: 18,
                  color: isDark ? Colors.white54 : Colors.black54)),
          const SizedBox(height: 8),
          Text('Connect to a 1Claw server to get started',
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(CupertinoIcons.link),
            label: const Text('Configure Server'),
          ),
        ],
      ),
    );
  }
}
