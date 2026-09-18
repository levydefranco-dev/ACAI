import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento local persistente (SharedPreferences).
/// Contatos e mensagens NÃO podem sumir ao fechar o app.
class LocalDb {
  static const _contactsKey = 'acai_contacts_v1';
  static const _messagesPrefix = 'acai_msgs_v1_';
  static const _myIdKey = 'acai_my_id_v1';

  // ========== MEU ID ==========
  static Future<String?> getMyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_myIdKey);
  }

  static Future<void> setMyId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_myIdKey, id);
  }

  // ========== CONTATOS (persistentes) ==========
  static Future<List<Map<String, dynamic>>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contactsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveContacts(List<Map<String, dynamic>> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contactsKey, jsonEncode(contacts));
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

  // ========== MENSAGENS (persistentes) ==========
  static Future<List<Map<String, dynamic>>> getMessages(String contactId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_messagesPrefix$contactId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMessages(
      String contactId, List<Map<String, dynamic>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_messagesPrefix$contactId', jsonEncode(messages));
  }

  static Future<void> addMessage({
    required String contactId,
    required String text,
    required bool isMe,
    String status = 'sent',
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
}
