import 'package:flutter/foundation.dart';
import '../models/agent_profile.dart';
import '../services/websocket_service.dart';

/// Manages the list of agent profiles and their online status.
/// Reactively updates when WebSocket status messages arrive.
class ProfilesProvider extends ChangeNotifier {
  final WebSocketService _wsService;
  List<AgentProfile> _profiles = [];
  String _activeProfileId = '';

  ProfilesProvider(this._wsService) {
    _wsService.onConnectionChange = (connected) {
      if (connected) {
        _wsService.requestStatus();
      }
      notifyListeners();
    };

    _wsService.onMessage = (msg) {
      if (msg.type == 'status') {
        // Profiles data comes separately through status updates
      }
    };
  }

  List<AgentProfile> get profiles => List.unmodifiable(_profiles);
  String get activeProfileId => _activeProfileId;
  AgentProfile? get activeProfile {
    try {
      return _profiles.firstWhere((p) => p.id == _activeProfileId);
    } catch (_) {
      return null;
    }
  }

  bool get isConnected => _wsService.isConnected;

  /// Set or update profiles from server data.
  void updateProfiles(List<AgentProfile> profiles) {
    _profiles = profiles;
    notifyListeners();
  }

  /// Update the online/offline status of a profile.
  void updateProfileStatus(String profileId, bool online) {
    for (final p in _profiles) {
      if (p.id == profileId) {
        p.online = online;
        notifyListeners();
        return;
      }
    }
  }

  /// Set the active profile (the one the user is chatting with).
  void setActiveProfile(String profileId) {
    _activeProfileId = profileId;
    _wsService.switchProfile(profileId);
    notifyListeners();
  }

  /// Load default profiles (fallback when server is unavailable).
  void loadDefaultProfiles() {
    _profiles = [
      AgentProfile(
        id: 'assistant',
        name: 'AI Assistant',
        emoji: '🤖',
        description: 'General purpose assistant',
        color: '#0078D7',
        online: false,
      ),
      AgentProfile(
        id: 'writer',
        name: 'Creative Writer',
        emoji: '✍️',
        description: 'Helps with writing and editing',
        color: '#7B1FA2',
        online: false,
      ),
      AgentProfile(
        id: 'coder',
        name: 'Code Expert',
        emoji: '💻',
        description: 'Programming and technical help',
        color: '#388E3C',
        online: false,
      ),
      AgentProfile(
        id: 'designer',
        name: 'Design Mentor',
        emoji: '🎨',
        description: 'UI/UX design advice',
        color: '#F57C00',
        online: false,
      ),
    ];
    notifyListeners();
  }
}
