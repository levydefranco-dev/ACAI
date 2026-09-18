import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import '../storage/local_db.dart';
import '../attachments/attachment_service.dart';
import '../calls/call_signaling.dart';
import '../calls/webrtc_call_manager.dart';
import '../calls/call_screen.dart';
import '../calls/incoming_call_handler.dart';
import 'message_service.dart';

class ChatScreen extends StatefulWidget {
  final String contactId;
  final String contactName;

  const ChatScreen({super.key, required this.contactId, required this.contactName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _myId;
  Timer? _pollTimer;
  int _lastFetch = 0;
  final Set<String> _selected = {};
  bool get _selectMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _myId = await LocalDb.getMyId();
    await _loadMessages();
    if (_myId != null) {
      await MessageService.markChatAsRead(_myId!, widget.contactId);
    }
    _lastFetch = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400 * 7;
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _fetchRemote();
      await MessageService.refreshOutgoingStatuses(widget.contactId);
      await _loadMessages();
    });
    _fetchRemote();
  }

  Future<void> _fetchRemote() async {
    if (_myId == null) return;
    final count = await MessageService.fetchNewMessages(myId: _myId!, since: _lastFetch);
    _lastFetch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (count > 0) {
      await MessageService.markChatAsRead(_myId!, widget.contactId);
      await _loadMessages();
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await LocalDb.getMessages(widget.contactId);
    if (mounted) {
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _myId == null || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    final ok = await MessageService.sendText(myId: _myId!, contactId: widget.contactId, text: text);
    await _loadMessages();
    if (mounted) {
      setState(() => _sending = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sem conexão. Mensagem será reenviada.')),
        );
      }
    }
  }

  Future<void> _sendFile(File file, String filename, String mime) async {
    if (_myId == null) return;
    setState(() => _sending = true);
    final id = await AttachmentService.sendFile(
      myId: _myId!,
      contactId: widget.contactId,
      file: file,
      filename: filename,
      mime: mime,
    );
    if (id != null) {
      await LocalDb.addMessage(
        contactId: widget.contactId,
        text: '[Anexo:$id|$filename|]',
        isMe: true,
        status: 'sent',
      );
      await _loadMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enviado'), backgroundColor: Colors.green),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao enviar')),
      );
    }
    if (mounted) setState(() => _sending = false);
  }

  // ========== ÁUDIO (sem package record — evita quebra de build) ==========
  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m4a', 'mp3', 'aac', 'wav', 'ogg', 'opus'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final f = result.files.first;
    await _sendFile(File(f.path!), f.name, 'audio/${f.extension ?? "mpeg"}');
  }

  /// Grava "áudio" via câmera em modo vídeo curto (só áudio útil se gravar sem mexer muito)
  Future<void> _recordVoiceViaCamera() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de câmera e microfone necessárias')),
        );
      }
      return;
    }
    final x = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 3),
    );
    if (x == null) return;
    final name = 'voz_${DateTime.now().millisecondsSinceEpoch}.mp4';
    await _sendFile(File(x.path), name, 'video/mp4');
  }

  Future<void> _audioMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Áudio / voz', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.mic, color: Color(0xFF6B21A8)),
              title: const Text('Gravar com a câmera (vídeo+voz)'),
              subtitle: const Text('Abre a câmera; grave e envie'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.audio_file, color: Color(0xFF6B21A8)),
              title: const Text('Escolher arquivo de áudio'),
              subtitle: const Text('m4a, mp3, wav...'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'camera') await _recordVoiceViaCamera();
    if (choice == 'file') await _pickAudioFile();
  }

  // ========== CÂMERA ==========
  Future<void> _openCameraMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Color(0xFF6B21A8)),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Color(0xFF6B21A8)),
              title: const Text('Gravar vídeo'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeria (foto)'),
              onTap: () => Navigator.pop(ctx, 'gallery_photo'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Galeria (vídeo)'),
              onTap: () => Navigator.pop(ctx, 'gallery_video'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Arquivo (PDF, etc.)'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'photo' || choice == 'gallery_photo') {
      final cam = choice == 'photo' ? await Permission.camera.request() : null;
      if (choice == 'photo' && cam != null && !cam.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissão de câmera necessária')),
          );
        }
        return;
      }
      final x = await _picker.pickImage(
        source: choice == 'photo' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (x == null) return;
      final file = File(x.path);
      final name = 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _sendFile(file, name, 'image/jpeg');
    } else if (choice == 'video' || choice == 'gallery_video') {
      if (choice == 'video') {
        final cam = await Permission.camera.request();
        final mic = await Permission.microphone.request();
        if (!cam.isGranted || !mic.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permissão de câmera/microfone necessária')),
            );
          }
          return;
        }
      }
      final x = await _picker.pickVideo(
        source: choice == 'video' ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(minutes: 2),
      );
      if (x == null) return;
      final file = File(x.path);
      final name = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await _sendFile(file, name, 'video/mp4');
    } else if (choice == 'file') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf', 'doc', 'docx', 'mp3', 'mp4', 'txt', 'm4a'],
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final f = result.files.first;
      await _sendFile(File(f.path!), f.name, f.extension ?? 'bin');
    }
  }

  Future<void> _openAttachment(String text) async {
    final inner = text.replaceFirst('[Anexo:', '').replaceAll(']', '');
    final parts = inner.split('|');
    if (parts.isEmpty || _myId == null) return;
    final attachId = parts[0];
    final filename = parts.length > 1 ? parts[1] : 'arquivo';
    final nonce = parts.length > 2 ? parts[2] : '';

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Baixando...')),
    );

    final file = await AttachmentService.downloadAndDecrypt(
      attachmentId: attachId,
      nonce: nonce.isNotEmpty ? nonce : 'AA==',
      myId: _myId!,
      contactId: widget.contactId,
      filename: filename,
    );

    if (file != null && mounted) {
      await OpenFilex.open(file.path);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir')),
      );
    }
  }

  Future<void> _deleteSelected() async {
    for (final id in _selected) {
      await MessageService.deleteMessage(widget.contactId, id);
    }
    setState(() => _selected.clear());
    await _loadMessages();
  }

  Future<void> _startCall({bool video = false}) async {
    if (_myId == null) return;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microfone necessário')));
      return;
    }
    if (video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Câmera necessária')));
        return;
      }
    }

    final handler = IncomingCallHandler();
    final manager = WebRTCCallManager(callHandler: handler);
    await manager.init();

    CallSignaling.onSignal = (signal) {
      if (signal['from_id'] == widget.contactId) manager.handleSignal(signal);
    };
    CallSignaling.startListening(_myId!);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(manager: manager, contactName: widget.contactName),
      ),
    );

    try {
      await manager.startCall(myId: _myId!, toId: widget.contactId, video: video);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha: $e')));
      }
    }
  }

  String _formatTime(String iso) {
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return '';
    }
  }

  bool _isAttach(String text) => text.startsWith('[Anexo:');

  IconData _attachIcon(String text) {
    final name = text.toLowerCase();
    if (name.contains('.m4a') || name.contains('audio') || name.contains('.mp3')) {
      return Icons.mic;
    }
    if (name.contains('.mp4') || name.contains('video')) return Icons.videocam;
    if (name.contains('.jpg') || name.contains('.png') || name.contains('foto')) {
      return Icons.image;
    }
    return Icons.attach_file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selected.length} selecionada(s)')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.contactName, style: const TextStyle(fontSize: 17)),
                  Text(widget.contactId, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        leading: _selectMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selected.clear()))
            : null,
        actions: _selectMode
            ? [IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected)]
            : [
                IconButton(icon: const Icon(Icons.call), onPressed: () => _startCall(video: false)),
                IconButton(icon: const Icon(Icons.videocam), onPressed: () => _startCall(video: true)),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchRemote),
              ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhuma mensagem ainda.\nEnvie texto, áudio, foto ou vídeo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['is_me'] == true;
                          final text = (msg['text'] ?? '') as String;
                          final id = (msg['id'] ?? '') as String;
                          final selected = _selected.contains(id);
                          final isAttach = _isAttach(text);

                          return GestureDetector(
                            onLongPress: () {
                              setState(() {
                                if (selected) {
                                  _selected.remove(id);
                                } else {
                                  _selected.add(id);
                                }
                              });
                            },
                            onTap: () {
                              if (_selectMode) {
                                setState(() {
                                  if (selected) {
                                    _selected.remove(id);
                                  } else {
                                    _selected.add(id);
                                  }
                                });
                              } else if (isAttach) {
                                _openAttachment(text);
                              }
                            },
                            child: Container(
                              color: selected ? Colors.purple.withOpacity(0.15) : null,
                              child: Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                  decoration: BoxDecoration(
                                    color: isMe ? const Color(0xFF6B21A8) : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(16),
                                    border: selected ? Border.all(color: Colors.purple, width: 2) : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isAttach) ...[
                                            Icon(_attachIcon(text), size: 18, color: isMe ? Colors.white70 : Colors.black54),
                                            const SizedBox(width: 6),
                                          ],
                                          Flexible(
                                            child: Text(
                                              isAttach
                                                  ? (text.split('|').length > 1 ? text.split('|')[1] : 'Anexo')
                                                  : text,
                                              style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15),
                                            ),
                                          ),
                                          if (isAttach && !isMe) ...[
                                            const SizedBox(width: 6),
                                            Icon(Icons.download, size: 16, color: Colors.black54),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _formatTime(msg['created_at'] ?? ''),
                                            style: TextStyle(color: isMe ? Colors.white70 : Colors.grey, fontSize: 11),
                                          ),
                                          if (isMe) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              msg['status'] == 'read' || msg['status'] == 'delivered'
                                                  ? Icons.done_all
                                                  : msg['status'] == 'pending'
                                                      ? Icons.access_time
                                                      : Icons.done,
                                              size: 14,
                                              color: msg['status'] == 'read' ? Colors.lightBlueAccent : Colors.white70,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Barra de gravação OU campo de mensagem
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: Color(0xFF6B21A8)),
                      tooltip: 'Anexo / Câmera',
                      onPressed: _sending ? null : _openCameraMenu,
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt, color: Color(0xFF6B21A8)),
                      tooltip: 'Câmera',
                      onPressed: _sending
                          ? null
                          : () async {
                              // atalho direto para foto
                              final cam = await Permission.camera.request();
                              if (!cam.isGranted) return;
                              final x = await _picker.pickImage(
                                source: ImageSource.camera,
                                imageQuality: 75,
                                maxWidth: 1600,
                              );
                              if (x == null) return;
                              await _sendFile(
                                File(x.path),
                                'foto_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                'image/jpeg',
                              );
                            },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Mensagem',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Microfone ou enviar texto
                    if (_controller.text.trim().isEmpty)
                      CircleAvatar(
                        backgroundColor: const Color(0xFF6B21A8),
                        child: IconButton(
                          icon: const Icon(Icons.mic, color: Colors.white, size: 22),
                          tooltip: 'Áudio / voz',
                          onPressed: _sending ? null : _audioMenu,
                        ),
                      )
                    else
                      CircleAvatar(
                        backgroundColor: const Color(0xFF6B21A8),
                        child: IconButton(
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: _sending ? null : _send,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
