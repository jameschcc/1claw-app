import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';

class ServerConfig {
  const ServerConfig({
    required this.wsUrl,
    required this.apiUrl,
  });

  final String wsUrl;
  final String apiUrl;
}

class ServerConfigStore {
  static const String _wsUrlKey = 'server.ws_url';
  static const String _apiUrlKey = 'server.api_url';

  static Future<ServerConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final wsUrl = prefs.getString(_wsUrlKey)?.trim();
    final apiUrl = prefs.getString(_apiUrlKey)?.trim();

    return ServerConfig(
      wsUrl: (wsUrl == null || wsUrl.isEmpty)
          ? AppConstants.defaultWsUrl
          : wsUrl,
      apiUrl: (apiUrl == null || apiUrl.isEmpty)
          ? AppConstants.defaultApiUrl
          : apiUrl,
    );
  }

  static Future<void> save({
    required String wsUrl,
    required String apiUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wsUrlKey, wsUrl.trim());
    await prefs.setString(_apiUrlKey, apiUrl.trim());
  }
}