import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../crypto/simple_crypto.dart';

class AttachmentService {
  static const baseUrl = 'https://www.ventureprojetos.com.br/app/api';

  /// Cifra e envia um arquivo
  static Future<String?> sendFile({
    required String myId,
    required String contactId,
    required File file,
    required String filename,
    required String mime,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      // Cifra o conteúdo como se fosse texto em base64 (MVP)
      final b64 = base64Encode(bytes);
      final encrypted = await SimpleCrypto.encrypt(
        plaintext: b64,
        myId: myId,
        contactId: contactId,
      );

      final cipherBytes = base64Decode(encrypted['ciphertext']!);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/upload_${DateTime.now().millisecondsSinceEpoch}.bin');
      await tempFile.writeAsBytes(cipherBytes);

      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/messages/upload.php'));
      req.fields['from_id'] = myId;
      req.fields['to_id'] = contactId;
      req.fields['nonce'] = encrypted['nonce']!;
      req.fields['filename'] = filename;
      req.fields['mime'] = mime;
      req.files.add(await http.MultipartFile.fromPath('ciphertext', tempFile.path));

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);

      try { await tempFile.delete(); } catch (_) {}

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['attachment_id'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Baixa e decifra um anexo
  static Future<File?> downloadAndDecrypt({
    required String attachmentId,
    required String nonce,
    required String myId,
    required String contactId,
    required String filename,
  }) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/messages/download.php?id=$attachmentId'))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;

      // O arquivo baixado é o ciphertext (com MAC no início, conforme SimpleCrypto)
      final cipherB64 = base64Encode(res.bodyBytes);
      final plainB64 = await SimpleCrypto.decrypt(
        ciphertextB64: cipherB64,
        nonceB64: nonce,
        myId: myId,
        contactId: contactId,
      );
      if (plainB64 == null) return null;

      final bytes = base64Decode(plainB64);
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/acai_$attachmentId\_$filename');
      await out.writeAsBytes(bytes);
      return out;
    } catch (_) {
      return null;
    }
  }
}
