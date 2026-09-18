import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../crypto/simple_crypto.dart';
import '../storage/local_db.dart';
import '../offline/offline_queue.dart';

class MessageService {
  // Endpoints com nomes neutros (HostGator bloqueia messages/send.php)
  static const String baseUrl = 'https://www.ventureprojetos.com.br/app/api';
  static const String boxUrl = '$baseUrl/box.php';
  static const String ackUrl = '$baseUrl/ack.php';

  static Future<String?> ping() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/version.php')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return null;
      return 'Servidor respondeu ${res.statusCode}';
    } catch (e) {
      return 'Sem conexão: $e';
    }
  }

  static Future<bool> sendText({
    required String myId,
    required String contactId,
    required String text,
  }) async {
    final localId = DateTime.now().millisecondsSinceEpoch.toString();

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

      final res = await http
          .post(
            Uri.parse(boxUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'},
            body: {
              'from_id': myId,
              'to_id': contactId,
              'ciphertext': encrypted['ciphertext']!,
              'nonce': encrypted['nonce']!,
              'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
              'type': 'text',
            },
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('AÇAI box send ${res.statusCode} ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final remoteId = data['message_id'] as String?;
        final msgs = await LocalDb.getMessages(contactId);
        if (msgs.isNotEmpty) {
          msgs[msgs.length - 1]['status'] = 'sent';
          if (remoteId != null) msgs[msgs.length - 1]['remote_id'] = remoteId;
          await LocalDb.saveMessages(contactId, msgs);
        }
        return true;
      }

      await OfflineQueue.enqueue(myId: myId, contactId: contactId, text: text, localMsgId: localId);
      return false;
    } catch (e) {
      debugPrint('AÇAI send error: $e');
      await OfflineQueue.enqueue(myId: myId, contactId: contactId, text: text, localMsgId: localId);
      return false;
    }
  }

  static Future<int> fetchNewMessages({required String myId, int since = 0}) async {
    try {
      final uri = Uri.parse(boxUrl).replace(queryParameters: {
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
        final msgId = m['id'] as String?;
        if (fromId == null) continue;

        if (type == 'attachment') {
          final label = '[Anexo:${m['attachment_id'] ?? ''}|${m['filename'] ?? 'arquivo'}|${m['nonce'] ?? ''}]';
          final existing = await LocalDb.getMessages(fromId);
          final already = existing.any((e) => (e['text'] as String?)?.contains(m['attachment_id'] ?? '###') == true);
          if (!already) {
            await LocalDb.addMessage(contactId: fromId, text: label, isMe: false, status: 'delivered');
            count++;
          }
          if (msgId != null) deliveredIds.add(msgId);
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
        if (plain == null) continue;

        final existing = await LocalDb.getMessages(fromId);
        final already = existing.any((e) => e['text'] == plain && e['is_me'] == false);
        if (!already) {
          await LocalDb.addMessage(contactId: fromId, text: plain, isMe: false, status: 'delivered');
          count++;
          if (msgId != null) deliveredIds.add(msgId);
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

  static Future<void> markChatAsRead(String myId, String contactId) async {
    // Marca mensagens recebidas como lidas localmente e no servidor
    final msgs = await LocalDb.getMessages(contactId);
    final ids = <String>[];
    var changed = false;
    for (final m in msgs) {
      if (m['is_me'] != true && m['status'] != 'read') {
        m['status'] = 'read';
        changed = true;
        if (m['remote_id'] != null) ids.add(m['remote_id']);
      }
    }
    if (changed) await LocalDb.saveMessages(contactId, msgs);
    if (ids.isNotEmpty) await _sendAck(myId, ids, 'read');
  }

  /// Remetente consulta se as mensagens foram entregues/lidas
  static Future<void> refreshOutgoingStatuses(String contactId) async {
    final msgs = await LocalDb.getMessages(contactId);
    final ids = msgs
        .where((m) => m['is_me'] == true && m['remote_id'] != null)
        .map((m) => m['remote_id'] as String)
        .toList();
    if (ids.isEmpty) return;

    try {
      final uri = Uri.parse(ackUrl).replace(queryParameters: {'ids': ids.join(',')});
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final statuses = data['statuses'] as Map<String, dynamic>? ?? {};
      var changed = false;
      for (final m in msgs) {
        final rid = m['remote_id'] as String?;
        if (rid != null && statuses[rid] != null) {
          final st = statuses[rid]['status'] as String?;
          if (st != null && m['status'] != st) {
            m['status'] = st;
            changed = true;
          }
        }
      }
      if (changed) await LocalDb.saveMessages(contactId, msgs);
    } catch (_) {}
  }

  static Future<void> _sendAck(String userId, List<String> ids, String status) async {
    try {
      await http
          .post(
            Uri.parse(ackUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'user_id': userId,
              'message_ids': ids.join(','),
              'status': status,
            },
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  static Future<void> deleteMessage(String contactId, String messageId) async {
    final msgs = await LocalDb.getMessages(contactId);
    msgs.removeWhere((m) => m['id'] == messageId);
    await LocalDb.saveMessages(contactId, msgs);
  }

  static Future<void> clearChat(String contactId) async {
    await LocalDb.saveMessages(contactId, []);
  }
}
