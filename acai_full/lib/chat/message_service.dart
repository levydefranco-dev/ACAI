import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../crypto/simple_crypto.dart';
import '../storage/local_db.dart';
import '../offline/offline_queue.dart';

class MessageService {
  static const String baseUrl = 'https://www.ventureprojetos.com.br/app/api';

  /// Testa se o backend está acessível
  static Future<String?> ping() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/version.php'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return null;
      return 'Servidor respondeu ${res.statusCode}';
    } catch (e) {
      return 'Sem conexão com o servidor: $e';
    }
  }

  static Future<bool> sendText({
    required String myId,
    required String contactId,
    required String text,
  }) async {
    final localId = DateTime.now().millisecondsSinceEpoch.toString();

    // Sempre salva local primeiro (para não perder a mensagem)
    await LocalDb.addMessage(
      contactId: contactId,
      text: text,
      isMe: true,
      status: 'pending',
    );

    try {
      final encrypted = await SimpleCrypto.encrypt(
        plaintext: text,
        myId: myId,
        contactId: contactId,
      );

      // Form-urlencoded evita bloqueio anti-bot da HostGator em JSON puro
      final body = {
        'from_id': myId,
        'to_id': contactId,
        'ciphertext': encrypted['ciphertext']!,
        'nonce': encrypted['nonce']!,
        'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      };

      debugPrint('AÇAI send → $baseUrl/messages/send.php');
      debugPrint('AÇAI body from=$myId to=$contactId');

      final res = await http
          .post(
            Uri.parse('$baseUrl/messages/send.php'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('AÇAI send status=${res.statusCode} body=${res.body}');

      if (res.statusCode == 200) {
        // Atualiza última mensagem para 'sent'
        final msgs = await LocalDb.getMessages(contactId);
        if (msgs.isNotEmpty) {
          msgs[msgs.length - 1]['status'] = 'sent';
          await LocalDb.saveMessages(contactId, msgs);
        }
        return true;
      }

      // Falha HTTP → fila offline
      await OfflineQueue.enqueue(
        myId: myId,
        contactId: contactId,
        text: text,
        localMsgId: localId,
      );
      return false;
    } catch (e) {
      debugPrint('AÇAI send error: $e');
      await OfflineQueue.enqueue(
        myId: myId,
        contactId: contactId,
        text: text,
        localMsgId: localId,
      );
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

      debugPrint('AÇAI fetch → $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      debugPrint('AÇAI fetch status=${res.statusCode}');

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
          final existing = await LocalDb.getMessages(fromId);
          final label = '[Anexo: ${m['filename'] ?? 'arquivo'}]';
          final already = existing.any((e) => e['text'] == label && e['is_me'] == false);
          if (!already) {
            await LocalDb.addMessage(
              contactId: fromId,
              text: label,
              isMe: false,
              status: 'delivered',
            );
            count++;
          }
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

      if (deliveredIds.isNotEmpty) {
        await _sendAck(myId, deliveredIds, 'delivered');
      }
      return count;
    } catch (e) {
      debugPrint('AÇAI fetch error: $e');
      return 0;
    }
  }

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
}
