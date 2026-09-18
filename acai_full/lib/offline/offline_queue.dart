import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../crypto/simple_crypto.dart';
import '../storage/local_db.dart';

/// Fila de mensagens pendentes com reenvio automático.
class OfflineQueue {
  static const _storage = FlutterSecureStorage();
  static const _key = 'acai_outbox';
  static const baseUrl = 'https://www.ventureprojetos.com.br/app/api';
  static Timer? _timer;

  static Future<List<Map<String, dynamic>>> _load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    await _storage.write(key: _key, value: jsonEncode(list));
  }

  /// Enfileira mensagem para envio posterior
  static Future<void> enqueue({
    required String myId,
    required String contactId,
    required String text,
    required String localMsgId,
  }) async {
    final list = await _load();
    list.add({
      'local_id': localMsgId,
      'my_id': myId,
      'contact_id': contactId,
      'text': text,
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _save(list);
  }

  /// Tenta reenviar tudo que está pendente
  static Future<int> processQueue() async {
    final list = await _load();
    if (list.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    var sent = 0;

    for (final item in list) {
      try {
        final encrypted = await SimpleCrypto.encrypt(
          plaintext: item['text'],
          myId: item['my_id'],
          contactId: item['contact_id'],
        );

        final res = await http
            .post(
              Uri.parse('$baseUrl/messages/send.php'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'from_id': item['my_id'],
                'to_id': item['contact_id'],
                'ciphertext': encrypted['ciphertext'],
                'nonce': encrypted['nonce'],
                'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          sent++;
          // Atualiza status local para 'sent'
          // (simplificado: a UI recarrega as mensagens)
        } else {
          item['attempts'] = (item['attempts'] ?? 0) + 1;
          if (item['attempts'] < 15) remaining.add(item);
        }
      } catch (_) {
        item['attempts'] = (item['attempts'] ?? 0) + 1;
        if (item['attempts'] < 15) remaining.add(item);
      }
    }

    await _save(remaining);
    return sent;
  }

  /// Inicia processamento periódico (chamar ao abrir o app)
  static void startAutoRetry() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => processQueue());
    processQueue(); // imediato
  }

  static void stopAutoRetry() {
    _timer?.cancel();
  }
}
