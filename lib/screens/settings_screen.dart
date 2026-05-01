import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../providers/font_settings_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/theme_provider.dart';
import '../services/server_config_store.dart';
import '../services/notification_service.dart';
import '../widgets/font_picker_dialog.dart';
import '../widgets/toast.dart';

/// Settings screen for server configuration and app preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _wsUrlController;
  late TextEditingController _apiUrlController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _wsUrlController =
        TextEditingController(text: AppConstants.defaultWsUrl);
    _apiUrlController =
        TextEditingController(text: AppConstants.defaultApiUrl);
    _loadServerConfig();
  }

  @override
  void dispose() {
    _wsUrlController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: isWide ? _buildWideBody(isDark) : _buildNarrowBody(isDark),
    );
  }

  // ── Narrow (single column) ──────────────────────────────────────────
  Widget _buildNarrowBody(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildServerSection(isDark),
        const SizedBox(height: 24),
        _buildAppearanceSection(isDark),
        const SizedBox(height: 24),
        _buildNotificationsSection(isDark),
        const SizedBox(height: 24),
        _buildAboutSection(isDark),
        const SizedBox(height: 24),
        _buildConnectionSection(isDark),
      ],
    );
  }

  // ── Wide (two columns) ──────────────────────────────────────────────
  Widget _buildWideBody(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: Server (taller card)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildServerSection(isDark),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right column: everything else
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAppearanceSection(isDark),
                const SizedBox(height: 24),
                _buildNotificationsSection(isDark),
                const SizedBox(height: 24),
                _buildAboutSection(isDark),
                const SizedBox(height: 24),
                _buildConnectionSection(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section builders ────────────────────────────────────────────────

  Widget _buildServerSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Server Configuration'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _wsUrlController,
                  decoration: const InputDecoration(
                    labelText: 'WebSocket URL',
                    hintText: 'ws://localhost:8080/ws',
                    prefixIcon: Icon(CupertinoIcons.link),
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'http://localhost:8080',
                    prefixIcon: Icon(CupertinoIcons.gear),
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveServerConfig,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(CupertinoIcons.cloud_download),
                    label: Text(_isSaving ? 'Saving...' : 'Save & Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppearanceSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Appearance'),
        const SizedBox(height: 8),
        Card(
          child: Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              final dark = themeProvider.isDark;
              return SwitchListTile(
                title: const Text('Dark Theme'),
                subtitle: Text(dark ? 'Dark mode enabled' : 'Light mode enabled'),
                secondary: Icon(dark ? CupertinoIcons.moon : CupertinoIcons.sun_max),
                value: dark,
                onChanged: (value) => themeProvider.setDark(value),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Consumer<FontSettingsProvider>(
            builder: (context, fontProvider, _) {
              return ListTile(
                leading: const Icon(CupertinoIcons.textformat),
                title: const Text('UI Font'),
                subtitle: Text(fontProvider.uiFont),
                trailing: const Icon(CupertinoIcons.chevron_right),
                onTap: () async {
                  final selected = await showDialog<String>(
                    context: context,
                    builder: (_) => FontPickerDialog(
                      currentFont: fontProvider.uiFont,
                    ),
                  );
                  if (selected != null && context.mounted) {
                    context.read<FontSettingsProvider>().setUIFont(selected);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Notifications'),
        const SizedBox(height: 8),
        Card(
          child: StatefulBuilder(
            builder: (context, setInnerState) {
              final notif = NotificationService();
              return SwitchListTile(
                title: const Text('Message Notifications'),
                subtitle: Text(
                  notif.enabled
                      ? 'Show system notifications for new messages'
                      : 'Notifications are disabled',
                ),
                secondary: Icon(
                  notif.enabled
                      ? CupertinoIcons.bell_fill
                      : CupertinoIcons.bell_slash,
                ),
                value: notif.enabled,
                onChanged: (value) async {
                  await notif.setEnabled(value);
                  setInnerState(() {});
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('About'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      '1Claw',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'v1.0.0',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Multi-Agent Platform\n'
                  'Keep multiple AI agent profiles simultaneously online.\n'
                  'Chat with them anytime via a beautiful mobile interface.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.code, size: 14,
                        color: isDark ? Colors.white38 : Colors.black38),
                    const SizedBox(width: 4),
                    Text(
                      'Flutter + Go + Hermes',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Connection'),
        const SizedBox(height: 8),
        Card(
          child: Consumer<ProfilesProvider>(
            builder: (context, provider, _) {
              return ListTile(
                leading: Icon(
                  provider.isConnected
                      ? Icons.cloud_done
                      : Icons.cloud_off,
                  color: provider.isConnected
                      ? AppConstants.onlineGreen
                      : Colors.red,
                ),
                title: Text(
                  provider.isConnected ? 'Connected' : 'Disconnected',
                ),
                subtitle: Text(
                  provider.isConnected
                      ? '${provider.profiles.length} profiles available'
                      : 'Tap to reconnect',
                ),
                trailing: provider.isConnected
                    ? null
                    : TextButton(
                        onPressed: () => provider.reconnect(),
                        child: const Text('Reconnect'),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppConstants.primaryBlue,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _loadServerConfig() async {
    final config = await ServerConfigStore.load();
    if (!mounted) return;

    _wsUrlController.text = config.wsUrl;
    _apiUrlController.text = config.apiUrl;
  }

  Future<void> _saveServerConfig() async {
    final wsUrl = _wsUrlController.text.trim();
    final apiUrl = _apiUrlController.text.trim();

    if (wsUrl.isEmpty || apiUrl.isEmpty) {
      showToast(context, 'Please fill in all fields');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final profilesProvider = context.read<ProfilesProvider>();
      await ServerConfigStore.save(wsUrl: wsUrl, apiUrl: apiUrl);
      final connected = await profilesProvider.updateServerUrl(wsUrl)
          .timeout(const Duration(seconds: 10), onTimeout: () => false);

      if (!mounted) return;

      if (connected) {
        showToast(context, 'Settings saved', duration: const Duration(seconds: 2));
      } else {
        showToast(context, 'Saved. Will retry connection ${Uri.parse(wsUrl).host}...');
      }
    } catch (e) {
      if (!mounted) return;

      showToast(context, 'Failed to save settings: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
