import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../crypto/simple_crypto.dart';

class AttachmentService {
  static const baseUrl = 'https://www.ventureprojetos.com.br/app/api';
  static const boxUrl = '$baseUrl/box.php';
  // upload usa nome neutro também
  static const uploadUrl = '$baseUrl/up.php';
  static const downloadUrl = '$baseUrl/dl.php';

  static Future<String?> sendFile({
    required String myId,
    required String contactId,
    required File file,
    required String filename,
    required String mime,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final encrypted = await SimpleCrypto.encrypt(
        plaintext: b64,
        myId: myId,
        contactId: contactId,
      );

      final cipherBytes = base64Decode(encrypted['ciphertext']!);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/up_${DateTime.now().millisecondsSinceEpoch}.bin');
      await tempFile.writeAsBytes(cipherBytes);

      // Tenta upload do blob
      String? attachId;
      try {
        final req = http.MultipartRequest('POST', Uri.parse(uploadUrl));
        req.fields['from_id'] = myId;
        req.fields['to_id'] = contactId;
        req.fields['nonce'] = encrypted['nonce']!;
        req.fields['filename'] = filename;
        req.fields['mime'] = mime;
        req.files.add(await http.MultipartFile.fromPath('ciphertext', tempFile.path));
        final streamed = await req.send().timeout(const Duration(seconds: 90));
        final res = await http.Response.fromStream(streamed);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          attachId = data['attachment_id'] as String?;
        }
      } catch (_) {}

      try { await tempFile.delete(); } catch (_) {}

      // Se upload falhou, embute o ciphertext pequeno via box (só arquivos pequenos < 200KB)
      if (attachId == null && bytes.length < 200000) {
        final res = await http
            .post(
              Uri.parse(boxUrl),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {
                'from_id': myId,
                'to_id': contactId,
                'ciphertext': encrypted['ciphertext']!,
                'nonce': encrypted['nonce']!,
                'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
                'type': 'attachment',
                'filename': filename,
                'mime': mime,
              },
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return data['message_id'] as String? ?? 'inline';
        }
        return null;
      }

      if (attachId == null) return null;

      // Notifica o destinatário via box
      await http.post(
        Uri.parse(boxUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'from_id': myId,
          'to_id': contactId,
          'ciphertext': '',
          'nonce': encrypted['nonce']!,
          'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
          'type': 'attachment',
          'filename': filename,
          'mime': mime,
          'attachment_id': attachId,
        },
      ).timeout(const Duration(seconds: 15));

      return attachId;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> downloadAndDecrypt({
    required String attachmentId,
    required String nonce,
    required String myId,
    required String contactId,
    required String filename,
    String? inlineCiphertext,
  }) async {
    try {
      List<int> cipherBytes;

      if (inlineCiphertext != null && inlineCiphertext.isNotEmpty) {
        cipherBytes = base64Decode(inlineCiphertext);
      } else {
        final res = await http
            .get(Uri.parse('$downloadUrl?id=$attachmentId'))
            .timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) return null;
        cipherBytes = res.bodyBytes;
      }

      final cipherB64 = base64Encode(cipherBytes);
      final plainB64 = await SimpleCrypto.decrypt(
        ciphertextB64: cipherB64,
        nonceB64: nonce,
        myId: myId,
        contactId: contactId,
      );
      if (plainB64 == null) return null;

      final bytes = base64Decode(plainB64);
      final dir = await getApplicationDocumentsDirectory();
      final safeName = filename.replaceAll(RegExp(r'[/\\]'), '_');
      final out = File('${dir.path}/acai_${attachmentId}_$safeName');
      await out.writeAsBytes(bytes);
      return out;
    } catch (_) {
      return null;
    }
  }
}
