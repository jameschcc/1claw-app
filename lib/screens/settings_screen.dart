import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../providers/profiles_provider.dart';

/// Settings screen for server configuration and app preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _wsUrlController;
  late TextEditingController _apiUrlController;
  bool _isDark = true;

  @override
  void initState() {
    super.initState();
    _wsUrlController =
        TextEditingController(text: AppConstants.defaultWsUrl);
    _apiUrlController =
        TextEditingController(text: AppConstants.defaultApiUrl);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server Configuration
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
                      prefixIcon: Icon(Icons.link),
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
                      prefixIcon: Icon(Icons.api),
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
                      onPressed: _saveServerConfig,
                      icon: const Icon(Icons.save),
                      label: const Text('Save & Connect'),
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

          const SizedBox(height: 24),

          // Appearance
          _sectionHeader('Appearance'),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Dark Theme'),
              subtitle: Text(isDark ? 'Dark mode enabled' : 'Light mode enabled'),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              value: isDark,
              onChanged: (value) {
                setState(() => _isDark = value);
                // Theme switching would be handled via a ThemeProvider
                // For now, we just update the state
              },
            ),
          ),

          const SizedBox(height: 24),

          // About
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

          const SizedBox(height: 24),

          // Connection status
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
                          onPressed: () => provider.loadDefaultProfiles(),
                          child: const Text('Reconnect'),
                        ),
                );
              },
            ),
          ),
        ],
      ),
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

  void _saveServerConfig() {
    final wsUrl = _wsUrlController.text.trim();
    final apiUrl = _apiUrlController.text.trim();

    if (wsUrl.isEmpty || apiUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved'),
        backgroundColor: AppConstants.onlineGreen,
      ),
    );
  }
}
