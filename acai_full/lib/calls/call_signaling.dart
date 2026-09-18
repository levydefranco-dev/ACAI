import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Sinalização WebRTC via polling no backend PHP.
/// Tipos: ring | offer | answer | candidate | hangup
class CallSignaling {
  static const baseUrl = 'https://www.ventureprojetos.com.br/app/api';
  static Timer? _pollTimer;
  static int _since = 0;
  static void Function(Map<String, dynamic> signal)? onSignal;

  static Future<bool> send({
    required String fromId,
    required String toId,
    required String type,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/calls/signal.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'from_id': fromId,
              'to_id': toId,
              'type': type,
              'payload': payload ?? {},
            }),
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static void startListening(String myId) {
    _pollTimer?.cancel();
    _since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll(myId));
    _poll(myId);
  }

  static void stopListening() {
    _pollTimer?.cancel();
  }

  static Future<void> _poll(String myId) async {
    try {
      final uri = Uri.parse('$baseUrl/calls/signal.php').replace(queryParameters: {
        'user_id': myId,
        'since': _since.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final signals = data['signals'] as List? ?? [];
      if (data['server_time'] != null) {
        _since = data['server_time'] as int;
      }
      for (final s in signals) {
        onSignal?.call(Map<String, dynamic>.from(s));
      }
    } catch (_) {}
  }

  /// Inicia uma chamada (envia "ring")
  static Future<bool> ring({required String myId, required String toId}) {
    return send(fromId: myId, toId: toId, type: 'ring', payload: {'media': 'audio'});
  }

  static Future<bool> hangup({required String myId, required String toId}) {
    return send(fromId: myId, toId: toId, type: 'hangup');
  }
}
