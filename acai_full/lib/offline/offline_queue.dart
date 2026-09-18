import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../crypto/simple_crypto.dart';

class OfflineQueue {
  static const _key = 'acai_outbox_v1';
  static const boxUrl = 'https://www.ventureprojetos.com.br/app/api/box.php';
  static Timer? _timer;

  static Future<List<Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  static Future<void> enqueue({
    required String myId,
    required String contactId,
    required String text,
    required String localMsgId,
  }) async {
    final list = await _load();
    if (list.any((e) => e['local_id'] == localMsgId)) return;
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
              Uri.parse(boxUrl),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {
                'from_id': item['my_id'],
                'to_id': item['contact_id'],
                'ciphertext': encrypted['ciphertext']!,
                'nonce': encrypted['nonce']!,
                'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
                'type': 'text',
              },
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          sent++;
        } else {
          item['attempts'] = (item['attempts'] ?? 0) + 1;
          if ((item['attempts'] as int) < 20) remaining.add(item);
        }
      } catch (_) {
        item['attempts'] = (item['attempts'] ?? 0) + 1;
        if ((item['attempts'] as int) < 20) remaining.add(item);
      }
    }
    await _save(remaining);
    return sent;
  }

  static void startAutoRetry() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => processQueue());
    processQueue();
  }
}
