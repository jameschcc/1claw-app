import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:posh_voice_input/posh_voice_input.dart';

import 'dart:io';

import '../config/constants.dart';
import '../providers/font_settings_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
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

  // ── Export form state ─────────────────────────────────────────────
  final TextEditingController _exportPasswordController =
      TextEditingController();
  final TextEditingController _exportConfirmPasswordController =
      TextEditingController();
  String? _exportFolderPath;
  bool _isExporting = false;

  String? _passwordError;
  String? _confirmPasswordError;
  String? _folderError;

  bool get _exportValid =>
      _passwordError == null &&
      _confirmPasswordError == null &&
      _folderError == null &&
      _exportPasswordController.text.isNotEmpty &&
      _exportConfirmPasswordController.text.isNotEmpty &&
      _exportFolderPath != null;

  @override
  void initState() {
    super.initState();
    _wsUrlController =
        TextEditingController(text: AppConstants.defaultWsUrl);
    _apiUrlController =
        TextEditingController(text: AppConstants.defaultApiUrl);
    _loadServerConfig();

    _exportPasswordController.addListener(_validateExportForm);
    _exportConfirmPasswordController.addListener(_validateExportForm);
  }

  void _validateExportForm() {
    setState(() {
      final pw = _exportPasswordController.text;
      final confirm = _exportConfirmPasswordController.text;
      final path = _exportFolderPath;

      // Password validation
      if (pw.isEmpty) {
        _passwordError = null; // no error when empty — user hasn't typed yet
      } else if (pw.length < 6) {
        _passwordError = 'Password must be at least 6 characters';
      } else {
        _passwordError = null;
      }

      // Confirm password validation
      if (confirm.isEmpty) {
        _confirmPasswordError = null;
      } else if (pw != confirm) {
        _confirmPasswordError = 'Passwords do not match';
      } else {
        _confirmPasswordError = null;
      }

      // Folder validation
      if (path == null) {
        _folderError = null;
      } else if (!Directory(path).existsSync()) {
        _folderError = 'Selected folder does not exist';
      } else {
        _folderError = null;
      }
    });
  }

  @override
  void dispose() {
    _wsUrlController.dispose();
    _apiUrlController.dispose();
    _exportPasswordController.removeListener(_validateExportForm);
    _exportPasswordController.dispose();
    _exportConfirmPasswordController.removeListener(_validateExportForm);
    _exportConfirmPasswordController.dispose();
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
        _buildExportSection(isDark),
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
                _buildVoiceSection(isDark),
                const SizedBox(height: 24),
                _buildExportSection(isDark),
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

  // ── Voice Input Section ──────────────────────────────────────────

  Widget _buildVoiceSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Voice Input'),
        const SizedBox(height: 8),
        Card(
          child: Consumer<FontSettingsProvider>(
            builder: (context, fontProvider, _) {
              return PoshVoiceInputSettings(
                enabled: fontProvider.voicesEnabled,
                onChanged: (val) => fontProvider.setVoicesEnabled(val),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Export Section ─────────────────────────────────────────────────

  Widget _buildExportSection(bool isDark) {
    final bgColor = isDark ? Colors.white10 : Colors.red.shade50;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Export Data'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export all data as a zip archive',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Includes: databases, profiles, shared files, and config.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Password ─────────────────────────────────────────────
                TextField(
                  controller: _exportPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: '6+ characters',
                    prefixIcon: const Icon(CupertinoIcons.lock),
                    border: const OutlineInputBorder(),
                    errorText: _passwordError,
                    errorMaxLines: 2,
                  ),
                  obscureText: true,
                  style: TextStyle(color: textColor),
                  onSubmitted: (_) => _handleExport(),
                ),
                if (_passwordError != null) const SizedBox(height: 4),

                const SizedBox(height: 12),

                // ── Confirm Password ──────────────────────────────────────
                TextField(
                  controller: _exportConfirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: 'Re-enter password',
                    prefixIcon: const Icon(CupertinoIcons.lock),
                    border: const OutlineInputBorder(),
                    errorText: _confirmPasswordError,
                    errorMaxLines: 2,
                  ),
                  obscureText: true,
                  style: TextStyle(color: textColor),
                  onSubmitted: (_) => _handleExport(),
                ),
                if (_confirmPasswordError != null) const SizedBox(height: 4),

                const SizedBox(height: 12),

                // ── Folder Picker ─────────────────────────────────────────
                InkWell(
                  onTap: _pickExportFolder,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Export Folder',
                      hintText: 'Click to select a folder',
                      prefixIcon: const Icon(CupertinoIcons.folder),
                      suffixIcon: const Icon(CupertinoIcons.chevron_right),
                      border: const OutlineInputBorder(),
                      errorText: _folderError,
                      errorMaxLines: 2,
                    ),
                    child: Text(
                      _exportFolderPath ?? 'No folder selected',
                      style: TextStyle(
                        fontSize: 14,
                        color: _exportFolderPath != null
                            ? textColor
                            : (isDark ? Colors.white38 : Colors.black38),
                      ),
                    ),
                  ),
                ),
                if (_folderError != null) const SizedBox(height: 4),

                const SizedBox(height: 16),

                // ── Export Button ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (!_exportValid || _isExporting)
                        ? null
                        : _handleExport,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(CupertinoIcons.cloud_download),
                    label: Text(_isExporting ? 'Exporting...' : 'Export'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Summary hint ──────────────────────────────────────────
                if (!_exportValid && _hasAnyInput())
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: Colors.red.shade400),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _buildErrorSummary(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _hasAnyInput() {
    return _exportPasswordController.text.isNotEmpty ||
        _exportConfirmPasswordController.text.isNotEmpty ||
        _exportFolderPath != null;
  }

  String _buildErrorSummary() {
    final parts = <String>[];
    if (_passwordError != null) parts.add(_passwordError!);
    if (_confirmPasswordError != null) parts.add(_confirmPasswordError!);
    if (_folderError != null) parts.add(_folderError!);
    if (parts.isEmpty) {
      return 'Please fill in all required fields';
    }
    return parts.join('\n');
  }

  Future<void> _pickExportFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Export Folder',
    );
    if (result != null) {
      setState(() {
        _exportFolderPath = result;
      });
      _validateExportForm();
    }
  }

  Future<void> _handleExport() async {
    _validateExportForm();
    if (!_exportValid) return;

    final password = _exportPasswordController.text.trim();
    final folder = _exportFolderPath!;

    setState(() => _isExporting = true);

    try {
      final config = await ServerConfigStore.load();
      final apiService = ApiService(baseUrl: config.apiUrl);

      final zipBytes = await apiService.exportData(password);

      if (!mounted) return;

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final filePath = '$folder/hermes-export-$timestamp.zip';
      final file = File(filePath);
      await file.writeAsBytes(zipBytes);

      if (!mounted) return;
      showToast(
        context,
        'Exported to: $filePath',
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Export failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }
}
