import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/generation_backend.dart';

/// Service for managing generation backend settings
class GenerationService {
  final String baseUrl;
  final http.Client _client;

  GenerationService({required this.baseUrl}) : _client = http.Client();

  /// Get backends for a content type (image, audio, etc.)
  Future<GenerationBackendsResponse> getBackends(String type) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/generate/backends/$type'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get backends: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return GenerationBackendsResponse.fromJson(data);
    } catch (e) {
      debugPrint('[GenerationService] Error getting backends: $e');
      rethrow;
    }
  }

  /// Update a backend's configuration
  Future<void> updateBackend(
    String type,
    String name,
    Map<String, dynamic> config,
  ) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/api/generate/backends/$type/$name'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update backend: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[GenerationService] Error updating backend: $e');
      rethrow;
    }
  }

  /// Set the default backend for a content type
  Future<void> setDefaultBackend(String type, String backendName) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/api/generate/default/$type'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'backend': backendName}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to set default backend: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[GenerationService] Error setting default: $e');
      rethrow;
    }
  }

  /// Check backend availability/status
  Future<Map<String, dynamic>> checkBackendStatus(
    String type,
    String name,
  ) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/generate/backends/$type/$name/status'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to check backend: ${response.statusCode}');
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[GenerationService] Error checking backend: $e');
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }
}
