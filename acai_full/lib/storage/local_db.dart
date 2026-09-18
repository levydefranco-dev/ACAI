import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento local simples (contatos + mensagens)
/// Em produção substituir por SQLite/SQLCipher + E2E real
class LocalDb {
  static const _storage = FlutterSecureStorage();
  static const _contactsKey = 'acai_contacts';
  static const _messagesPrefix = 'acai_msgs_';

  // ========== CONTATOS ==========
  static Future<List<Map<String, dynamic>>> getContacts() async {
    final raw = await _storage.read(key: _contactsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> saveContacts(List<Map<String, dynamic>> contacts) async {
    await _storage.write(key: _contactsKey, value: jsonEncode(contacts));
  }

  static Future<void> addContact({
    required String id,
    required String displayName,
  }) async {
    final contacts = await getContacts();
    if (contacts.any((c) => c['id'] == id)) {
      throw Exception('Contato já existe');
    }
    contacts.add({
      'id': id,
      'name': displayName,
      'added_at': DateTime.now().toIso8601String(),
    });
    await saveContacts(contacts);
  }

  static Future<void> removeContact(String id) async {
    final contacts = await getContacts();
    contacts.removeWhere((c) => c['id'] == id);
    await saveContacts(contacts);
  }

  // ========== MENSAGENS ==========
  static Future<List<Map<String, dynamic>>> getMessages(String contactId) async {
    final raw = await _storage.read(key: '$_messagesPrefix$contactId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> saveMessages(String contactId, List<Map<String, dynamic>> messages) async {
    await _storage.write(key: '$_messagesPrefix$contactId', value: jsonEncode(messages));
  }

  static Future<void> addMessage({
    required String contactId,
    required String text,
    required bool isMe,
    String status = 'sent', // sent | delivered | read
  }) async {
    final messages = await getMessages(contactId);
    messages.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': text,
      'is_me': isMe,
      'status': status,
      'created_at': DateTime.now().toIso8601String(),
    });
    await saveMessages(contactId, messages);
  }

  // Meu próprio ID
  static Future<String?> getMyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('acai_my_id');
  }

  static Future<void> setMyId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('acai_my_id', id);
  }
}
