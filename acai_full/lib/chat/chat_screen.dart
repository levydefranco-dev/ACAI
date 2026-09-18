import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
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

  const ChatScreen({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _myId;
  Timer? _pollTimer;
  int _lastFetch = 0;

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
    _lastFetch = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400;
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchRemote());
    _fetchRemote();
  }

  Future<void> _fetchRemote() async {
    if (_myId == null) return;
    final count = await MessageService.fetchNewMessages(myId: _myId!, since: _lastFetch);
    _lastFetch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (count > 0) await _loadMessages();
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
    await MessageService.sendText(myId: _myId!, contactId: widget.contactId, text: text);
    await _loadMessages();
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _pickAndSendFile() async {
    if (_myId == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'doc', 'docx', 'mp3', 'mp4', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    setState(() => _sending = true);
    final id = await AttachmentService.sendFile(
      myId: _myId!,
      contactId: widget.contactId,
      file: File(file.path!),
      filename: file.name,
      mime: file.extension ?? 'application/octet-stream',
    );

    if (id != null) {
      await LocalDb.addMessage(
        contactId: widget.contactId,
        text: '[Anexo: ${file.name}]',
        isMe: true,
        status: 'sent',
      );
      await _loadMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anexo enviado'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao enviar anexo')),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _startCall({bool video = false}) async {
    if (_myId == null) return;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de microfone necessária')),
      );
      return;
    }
    if (video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de câmera necessária')),
        );
        return;
      }
    }

    final handler = IncomingCallHandler();
    final manager = WebRTCCallManager(callHandler: handler);
    await manager.init();

    // Escuta sinais durante a chamada
    CallSignaling.onSignal = (signal) {
      if (signal['from_id'] == widget.contactId) {
        manager.handleSignal(signal);
      }
    };
    CallSignaling.startListening(_myId!);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          manager: manager,
          contactName: widget.contactName,
        ),
      ),
    );

    await manager.startCall(myId: _myId!, toId: widget.contactId, video: video);
  }

  String _formatTime(String iso) {
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contactName, style: const TextStyle(fontSize: 17)),
            Text(widget.contactId, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Chamada de voz',
            onPressed: () => _startCall(video: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Chamada de vídeo',
            onPressed: () => _startCall(video: true),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRemote,
          ),
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
                          'Nenhuma mensagem ainda.\nEnvie a primeira!',
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
                          final text = msg['text'] ?? '';
                          final isAttach = text.toString().startsWith('[Anexo:');
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe ? const Color(0xFF6B21A8) : Colors.grey[200],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isAttach)
                                        Icon(Icons.attach_file,
                                            size: 16,
                                            color: isMe ? Colors.white70 : Colors.black54),
                                      if (isAttach) const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          text,
                                          style: TextStyle(
                                            color: isMe ? Colors.white : Colors.black87,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatTime(msg['created_at'] ?? ''),
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          msg['status'] == 'read'
                                              ? Icons.done_all
                                              : msg['status'] == 'pending'
                                                  ? Icons.access_time
                                                  : Icons.done,
                                          size: 14,
                                          color: msg['status'] == 'read'
                                              ? Colors.lightBlueAccent
                                              : Colors.white70,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Campo + anexo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Color(0xFF6B21A8)),
                    onPressed: _sending ? null : _pickAndSendFile,
                    tooltip: 'Enviar anexo',
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
                    ),
                  ),
                  const SizedBox(width: 6),
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
