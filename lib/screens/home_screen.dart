import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/agent_profile.dart';
import '../providers/profiles_provider.dart';
import '../widgets/agent_card.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/chat_panel.dart';
import '../widgets/user_list_item.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  bool _dialogShown = false;
  late bool _isWide;
  Timer? _resizeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dialogShown = false;
    // Default to portrait; corrected on first post-frame
    _isWide = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _isWide = MediaQuery.of(context).size.width >= 600;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resizeTimer?.cancel();
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
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
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
              Container(
                width: 60,
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFD8D8D8),
                child: Column(
                  children: [
                    const Spacer(),
                    // Refresh button — triggers server profile reload
                    Consumer<ProfilesProvider>(
                      builder: (_, p, _) => Opacity(
                        opacity: 0.9,
                        child: IconButton(
                          icon: const Icon(CupertinoIcons.refresh,
                              size: 24),
                          tooltip: 'Refresh profiles from server',
                          onPressed:
                              p.isConnected ? () => p.requestStatus() : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: 0.9,
                      child: IconButton(
                        icon: const Icon(CupertinoIcons.gear,
                            size: 24),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

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
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: profiles.length,
                        itemBuilder: (context, index) {
                          final profile = profiles[index];
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
                child: ChatPanel(profile: activeProfile),
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
