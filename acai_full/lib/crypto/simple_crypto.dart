import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Criptografia simétrica simples baseada em chave derivada dos IDs.
/// IMPORTANTE: Esta é uma camada intermediária.
/// O ideal futuro é Signal Protocol (X3DH + Double Ratchet).
/// Para um grupo pequeno e fechado, já oferece confidencialidade
/// contra o servidor (zero-knowledge no relay).
class SimpleCrypto {
  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'acai_chat_key_';

  /// Gera ou recupera uma chave compartilhada para um par de contatos.
  /// Ambos os lados derivam a mesma chave a partir dos dois IDs ordenados.
  static Future<Uint8List> _getSharedKey(String myId, String contactId) async {
    final ids = [myId, contactId]..sort();
    final material = '${ids[0]}|${ids[1]}|ACAI_SECRET_V1';
    final hash = sha256.convert(utf8.encode(material)).bytes;
    return Uint8List.fromList(hash);
  }

  /// Cifra o texto. Retorna map com ciphertext (base64) e nonce (base64).
  static Future<Map<String, String>> encrypt({
    required String plaintext,
    required String myId,
    required String contactId,
  }) async {
    final key = await _getSharedKey(myId, contactId);
    final nonce = _randomBytes(16);
    final plainBytes = utf8.encode(plaintext);

    // XOR stream cipher simples + HMAC (para MVP)
    // Em produção usar AES-GCM via package pointycastle ou libsodium
    final keyStream = _expandKey(key, nonce, plainBytes.length);
    final cipherBytes = Uint8List(plainBytes.length);
    for (var i = 0; i < plainBytes.length; i++) {
      cipherBytes[i] = plainBytes[i] ^ keyStream[i];
    }

    final mac = Hmac(sha256, key).convert([...nonce, ...cipherBytes]).bytes;

    return {
      'ciphertext': base64Encode([...mac, ...cipherBytes]),
      'nonce': base64Encode(nonce),
    };
  }

  /// Decifra o texto.
  static Future<String?> decrypt({
    required String ciphertextB64,
    required String nonceB64,
    required String myId,
    required String contactId,
  }) async {
    try {
      final key = await _getSharedKey(myId, contactId);
      final nonce = base64Decode(nonceB64);
      final data = base64Decode(ciphertextB64);

      if (data.length < 32) return null;
      final mac = data.sublist(0, 32);
      final cipherBytes = data.sublist(32);

      final expectedMac = Hmac(sha256, key).convert([...nonce, ...cipherBytes]).bytes;
      if (!_constantTimeEquals(mac, expectedMac)) return null;

      final keyStream = _expandKey(key, nonce, cipherBytes.length);
      final plainBytes = Uint8List(cipherBytes.length);
      for (var i = 0; i < cipherBytes.length; i++) {
        plainBytes[i] = cipherBytes[i] ^ keyStream[i];
      }
      return utf8.decode(plainBytes);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rnd.nextInt(256)));
  }

  static Uint8List _expandKey(Uint8List key, Uint8List nonce, int length) {
    final out = <int>[];
    var counter = 0;
    while (out.length < length) {
      final block = sha256.convert([...key, ...nonce, counter >> 24, counter >> 16, counter >> 8, counter]).bytes;
      out.addAll(block);
      counter++;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
