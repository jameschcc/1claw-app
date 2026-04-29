import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _dialogShown = false;
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset dialog flag when widget is new
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 600;

    // Check for manual reconnect dialog once per flag
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ProfilesProvider>();
      if (provider.needsManualReconnect && !_dialogShown) {
        _dialogShown = true;
        _showReconnectDialog(context, provider);
      }
    });

    return isWide ? _buildLandscapeLayout() : _buildPortraitLayout();
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
                // Grid
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: provider.profiles.length,
                    itemBuilder: (context, index) {
                      final profile = provider.profiles[index];
                      final isPinned =
                          index < provider.pinnedProfiles.length;
                      return Column(
                        children: [
                          if (isPinned &&
                              index ==
                                  provider.pinnedProfiles.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: List.filled(
                                    3,
                                    Expanded(
                                      child: Divider(
                                        color: Colors.amber
                                            .withValues(alpha: 0.3),
                                        thickness: 0.5,
                                      ),
                                    )),
                              ),
                            ),
                          Expanded(
                            child: AgentCard(
                              profile: profile,
                              isActive: profile.id ==
                                  provider.activeProfileId,
                              onTap: () {
                                provider.setActiveProfile(profile.id);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                          profile: profile)),
                                );
                              },
                              onTogglePin: () =>
                                  provider.togglePin(profile.id),
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
                      child: const Row(
                        children: [
                          Text('1Claw',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ],
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
                    // Bottom bar: connection + settings
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                      child: Row(
                        children: [
                          Consumer<ProfilesProvider>(
                            builder: (_, p, _) => ConnectionIndicator(
                              isConnected: p.isConnected,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(CupertinoIcons.gear,
                                size: 20),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Vertical divider ──
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
