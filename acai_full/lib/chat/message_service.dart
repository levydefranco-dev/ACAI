import 'dart:convert';
import 'package:http/http.dart' as http;
import '../crypto/simple_crypto.dart';
import '../storage/local_db.dart';
import '../offline/offline_queue.dart';

class MessageService {
  static const String baseUrl = 'https://www.ventureprojetos.com.br/app/api';

  static Future<bool> sendText({
    required String myId,
    required String contactId,
    required String text,
  }) async {
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      final encrypted = await SimpleCrypto.encrypt(
        plaintext: text,
        myId: myId,
        contactId: contactId,
      );

      final body = {
        'from_id': myId,
        'to_id': contactId,
        'ciphertext': encrypted['ciphertext'],
        'nonce': encrypted['nonce'],
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };

      final res = await http
          .post(
            Uri.parse('$baseUrl/messages/send.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await LocalDb.addMessage(
          contactId: contactId,
          text: text,
          isMe: true,
          status: 'sent',
        );
        // Guarda o id remoto para depois atualizar status
        return true;
      }

      // Falhou → fila offline
      await LocalDb.addMessage(contactId: contactId, text: text, isMe: true, status: 'pending');
      await OfflineQueue.enqueue(myId: myId, contactId: contactId, text: text, localMsgId: localId);
      return false;
    } catch (_) {
      await LocalDb.addMessage(contactId: contactId, text: text, isMe: true, status: 'pending');
      await OfflineQueue.enqueue(myId: myId, contactId: contactId, text: text, localMsgId: localId);
      return false;
    }
  }

  static Future<int> fetchNewMessages({
    required String myId,
    int since = 0,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/messages/fetch.php').replace(queryParameters: {
        'user_id': myId,
        'since': since.toString(),
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return 0;

      final data = jsonDecode(res.body);
      final messages = data['messages'] as List? ?? [];
      var count = 0;
      final deliveredIds = <String>[];

      for (final m in messages) {
        final type = m['type'] as String? ?? 'text';
        final fromId = m['from_id'] as String?;
        if (fromId == null) continue;

        if (type == 'attachment') {
          // Salva metadado do anexo localmente
          await LocalDb.addMessage(
            contactId: fromId,
            text: '[Anexo: ${m['filename'] ?? 'arquivo'}]',
            isMe: false,
            status: 'delivered',
          );
          count++;
          if (m['id'] != null) deliveredIds.add(m['id']);
          continue;
        }

        final ciphertext = m['ciphertext'] as String?;
        final nonce = m['nonce'] as String?;
        if (ciphertext == null || nonce == null) continue;

        final plain = await SimpleCrypto.decrypt(
          ciphertextB64: ciphertext,
          nonceB64: nonce,
          myId: myId,
          contactId: fromId,
        );

        if (plain != null) {
          final existing = await LocalDb.getMessages(fromId);
          final already = existing.any((e) => e['text'] == plain && e['is_me'] == false);
          if (!already) {
            await LocalDb.addMessage(
              contactId: fromId,
              text: plain,
              isMe: false,
              status: 'delivered',
            );
            count++;
            if (m['id'] != null) deliveredIds.add(m['id']);
          }
        }
      }

      // Confirma entrega
      if (deliveredIds.isNotEmpty) {
        await _sendAck(myId, deliveredIds, 'delivered');
      }

      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Marca mensagens como lidas (chamar ao abrir o chat)
  static Future<void> markAsRead(String myId, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _sendAck(myId, messageIds, 'read');
  }

  static Future<void> _sendAck(String userId, List<String> ids, String status) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/messages/ack.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'message_ids': ids,
              'status': status,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Consulta status das mensagens enviadas
  static Future<Map<String, String>> fetchStatuses(List<String> messageIds) async {
    if (messageIds.isEmpty) return {};
    try {
      final uri = Uri.parse('$baseUrl/messages/status.php').replace(queryParameters: {
        'ids': messageIds.join(','),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return {};
      final data = jsonDecode(res.body);
      final statuses = data['statuses'] as Map<String, dynamic>? ?? {};
      return statuses.map((k, v) => MapEntry(k, (v['status'] as String?) ?? 'sent'));
    } catch (_) {
      return {};
    }
  }
}
