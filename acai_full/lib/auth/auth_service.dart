import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AuthResult { real, duress, fail, needsSetup }

class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyRealPin = 'acai_real_pin_hash';
  static const _keyDuressPin = 'acai_duress_pin_hash';
  static const _keySetupDone = 'acai_setup_done';

  /// Verifica se o usuário já configurou a senha
  static Future<bool> isSetupComplete() async {
    final done = await _storage.read(key: _keySetupDone);
    return done == 'true';
  }

  /// Hash SHA-256 da senha
  static String _hash(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  /// Salva as senhas na primeira configuração
  static Future<void> setupPins({
    required String realPin,
    String? duressPin,
  }) async {
    if (realPin.length != 8 || !RegExp(r'^\d{8}$').hasMatch(realPin)) {
      throw Exception('PIN real deve ter exatamente 8 dígitos');
    }
    if (duressPin != null && duressPin.isNotEmpty) {
      if (duressPin.length != 8 || !RegExp(r'^\d{8}$').hasMatch(duressPin)) {
        throw Exception('PIN de coação deve ter exatamente 8 dígitos');
      }
      if (duressPin == realPin) {
        throw Exception('PIN de coação deve ser diferente do PIN real');
      }
    }

    await _storage.write(key: _keyRealPin, value: _hash(realPin));
    if (duressPin != null && duressPin.isNotEmpty) {
      await _storage.write(key: _keyDuressPin, value: _hash(duressPin));
    } else {
      await _storage.delete(key: _keyDuressPin);
    }
    await _storage.write(key: _keySetupDone, value: 'true');
  }

  /// Autentica o PIN digitado
  static Future<AuthResult> authenticate(String pin) async {
    if (pin.length != 8) return AuthResult.fail;

    final setup = await isSetupComplete();
    if (!setup) return AuthResult.needsSetup;

    final realHash = await _storage.read(key: _keyRealPin);
    final duressHash = await _storage.read(key: _keyDuressPin);
    final inputHash = _hash(pin);

    if (realHash != null && inputHash == realHash) {
      return AuthResult.real;
    }
    if (duressHash != null && inputHash == duressHash) {
      return AuthResult.duress;
    }
    return AuthResult.fail;
  }

  /// Remove todas as senhas (para testes / reset)
  static Future<void> reset() async {
    await _storage.deleteAll();
  }
}
