import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_profile.dart';
import '../services/websocket_service.dart';

/// Manages the list of agent profiles and their online status.
class ProfilesProvider extends ChangeNotifier {
  final WebSocketService _wsService;
  List<AgentProfile> _profiles = [];
  Set<String> _pinnedIds = {};
  String _activeProfileId = '';
  bool _disposed = false;
  late final void Function(bool connected) _connectionListener;
  late final void Function(dynamic msg) _messageListener;

  ProfilesProvider(this._wsService) {
    _loadPins();
    _connectionListener = (connected) {
      if (connected) {
        _wsService.requestStatus();
      }
      _notifySafely();
    };
    _wsService.onConnectionChange = _connectionListener;

    _messageListener = (msg) {
      if (msg.type == 'status' && msg.profiles != null) {
        final profiles = msg.profiles!
            .map((p) => AgentProfile.fromJson(p as Map<String, dynamic>))
            .toList();
        // Preserve pin state
        for (final p in profiles) {
          p.isPinned = _pinnedIds.contains(p.id);
        }
        _profiles = profiles;
        _notifySafely();
      }
    };
    _wsService.addMessageListener(_messageListener);
  }

  /// Profiles sorted: pinned first, then rest.
  List<AgentProfile> get profiles {
    final pinned = <AgentProfile>[];
    final unpinned = <AgentProfile>[];
    for (final p in _profiles) {
      if (p.isPinned) {
        pinned.add(p);
      } else {
        unpinned.add(p);
      }
    }
    return [...pinned, ...unpinned];
  }

  List<AgentProfile> get pinnedProfiles =>
      _profiles.where((p) => p.isPinned).toList();

  String get activeProfileId => _activeProfileId;
  AgentProfile? get activeProfile {
    try {
      return _profiles.firstWhere((p) => p.id == _activeProfileId);
    } catch (_) {
      return null;
    }
  }

  bool get isConnected => _wsService.isConnected;
  String get serverUrl => _wsService.serverUrl;
  bool hasPinned() => _pinnedIds.isNotEmpty;

  Future<void> reconnect() async {
    await _wsService.reconnect();
  }

  /// Update server URL and reconnect. Returns true if connected successfully.
  Future<bool> updateServerUrl(String url) async {
    _wsService.setServerUrl(url);
    return await _wsService.reconnect();
  }

  /// Toggle pin status for a profile.
  void togglePin(String profileId) {
    if (_pinnedIds.contains(profileId)) {
      _pinnedIds.remove(profileId);
    } else {
      _pinnedIds.add(profileId);
    }
    for (final p in _profiles) {
      if (p.id == profileId) {
        p.isPinned = !p.isPinned;
        break;
      }
    }
    _savePins();
    _notifySafely();
  }

  void setActiveProfile(String profileId) {
    _activeProfileId = profileId;
    _wsService.switchProfile(profileId);
    _notifySafely();
  }

  void updateProfiles(List<AgentProfile> profiles) {
    for (final p in profiles) {
      p.isPinned = _pinnedIds.contains(p.id);
    }
    _profiles = profiles;
    _notifySafely();
  }

  void updateProfileStatus(String profileId, bool online) {
    for (final p in _profiles) {
      if (p.id == profileId) {
        p.online = online;
        _notifySafely();
        return;
      }
    }
  }

  void loadDefaultProfiles() {
    _profiles = [
      AgentProfile(id: 'assistant', name: 'AI Assistant', emoji: '🤖',
          description: 'General purpose assistant', color: '#0078D7'),
      AgentProfile(id: 'writer', name: 'Creative Writer', emoji: '✍️',
          description: 'Helps with writing and editing', color: '#7B1FA2'),
      AgentProfile(id: 'coder', name: 'Code Expert', emoji: '💻',
          description: 'Programming help', color: '#388E3C'),
      AgentProfile(id: 'designer', name: 'Design Mentor', emoji: '🎨',
          description: 'UI/UX design', color: '#F57C00'),
    ];
    for (final p in _profiles) {
      p.isPinned = _pinnedIds.contains(p.id);
    }
    _notifySafely();
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _pinnedIds = (prefs.getStringList('pinned_profiles') ?? []).toSet();
    _notifySafely();
  }

  Future<void> _savePins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_profiles', _pinnedIds.toList());
  }

  void _notifySafely() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (identical(_wsService.onConnectionChange, _connectionListener)) {
      _wsService.onConnectionChange = null;
    }
    _wsService.removeMessageListener(_messageListener);
    super.dispose();
  }
}
