import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class VersionChecker {
  static const String baseUrl = 'https://www.ventureprojetos.com.br/app/api';

  static Future<UpdateInfo?> check({required String userId}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final uri = Uri.parse('$baseUrl/version.php').replace(queryParameters: {
        'userId': userId,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final latest = data['latest'] as String?;
      final force = data['force'] == true;
      final needsUpdate = data['needs_update'] == true;
      final downloadUrl = data['download_url'] as String?;
      final message = data['message'] as String?;

      if (latest == null || downloadUrl == null) return null;

      if (force || needsUpdate) {
        return UpdateInfo(
          latestVersion: latest,
          currentVersion: currentVersion,
          downloadUrl: downloadUrl,
          force: force,
          message: message,
        );
      }
      return null;
    } catch (e) {
      debugPrint('VersionChecker error: $e');
      return null;
    }
  }
}

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final bool force;
  final String? message;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.force,
    this.message,
  });
}
