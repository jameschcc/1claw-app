import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent_profile.dart';

/// REST API client for 1Claw server.
/// Used for profile CRUD operations (non-real-time).
class ApiService {
  String _baseUrl;

  ApiService({String baseUrl = 'http://localhost:8080'}) : _baseUrl = baseUrl;

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  Future<List<AgentProfile>> fetchProfiles() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/profiles'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final profiles = (data['profiles'] as List<dynamic>?) ?? [];
        return profiles
            .map((p) => AgentProfile.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      throw Exception('Failed to fetch profiles: $e');
    }
    return [];
  }

  Future<AgentProfile> createProfile(AgentProfile profile) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/profiles'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(profile.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return AgentProfile.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      throw Exception('Failed to create profile: ${response.body}');
    } catch (e) {
      throw Exception('Failed to create profile: $e');
    }
  }

  /// Create a new Hermes profile on disk (cloned from an existing profile).
  /// [name] is the new profile name. [inheritFrom] is the source profile to clone from.
  Future<AgentProfile> createNewProfile(String name, {String? inheritFrom}) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (inheritFrom != null && inheritFrom.isNotEmpty) {
        body['inherit_from'] = inheritFrom;
      }
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/profiles'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        return AgentProfile.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Create failed (${response.statusCode})');
    } catch (e) {
      throw Exception('Failed to create profile: $e');
    }
  }

  /// Spawn a duplicate agent process for an existing profile (no files created on disk).
  /// Returns the spawned profile info including its new ID (e.g. "dev-2").
  Future<Map<String, dynamic>> spawnProfile(String profileId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/profiles/spawn'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'profile_id': profileId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Spawn failed (${response.statusCode})');
    } catch (e) {
      throw Exception('Failed to spawn profile: $e');
    }
  }

  Future<void> deleteProfile(String id) async {
    try {
      await http
          .delete(Uri.parse('$_baseUrl/api/profiles/$id'))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw Exception('Failed to delete profile: $e');
    }
  }

  Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Export all data as a zip archive. Returns the raw bytes of the zip file.
  Future<List<int>> exportData(String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/export'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Export failed (${response.statusCode})');
    } catch (e) {
      throw Exception('Export failed: $e');
    }
  }
}
