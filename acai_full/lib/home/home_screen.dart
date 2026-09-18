import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../security/about_security.dart';
import '../facade/facade_screen.dart';
import '../contacts/add_contact_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/message_service.dart';
import '../storage/local_db.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _contacts = [];
  String? _myId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var myId = await LocalDb.getMyId();
    if (myId == null) {
      myId = _generateId();
      await LocalDb.setMyId(myId);
      // Registra no servidor (para painel admin e presença)
      try {
        await http.post(
          Uri.parse('https://www.ventureprojetos.com.br/app/api/register.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id': myId, 'app_version': '1.0.1'}),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    final contacts = await LocalDb.getContacts();
    setState(() {
      _myId = myId;
      _contacts = contacts;
      _loading = false;
    });

    // Testa conexão com o backend (não bloqueia a UI)
    final err = await MessageService.ping();
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aviso: $err'),
          backgroundColor: Colors.orange[800],
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _generateId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    String seg() => List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'ACAI-${seg()}-${seg()}-${seg()}';
  }

  Future<void> _refresh() async {
    final contacts = await LocalDb.getContacts();
    setState(() => _contacts = contacts);
  }

  void _showMyId() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seu ID de conversação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              _myId ?? '',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 16),
            const Text(
              'Este é o seu ID de conversação. É pessoal e intransferível — compartilhe apenas com as pessoas do seu grupo de confiança, pelo canal que considerar mais seguro. Sem esse ID, ninguém pode iniciar uma conversa com você.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _myId ?? ''));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ID copiado')),
              );
            },
            child: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      appBar: AppBar(
        title: const Text('AÇAÍ'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'Meu ID',
            onPressed: _showMyId,
          ),
          IconButton(
            icon: const Icon(Icons.security),
            tooltip: 'Sobre a segurança',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutSecurityScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Voltar para fachada',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const FacadeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Conversas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Seu ID: ${_myId ?? "..."}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _contacts.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Nenhum contato ainda.\nToque no + para adicionar pelo ID.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, height: 1.5),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final c = _contacts[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF6B21A8),
                                  child: Text(
                                    (c['name'] as String).isNotEmpty
                                        ? (c['name'] as String)[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(c['id'] ?? '', style: const TextStyle(fontSize: 12)),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        contactId: c['id'],
                                        contactName: c['name'],
                                      ),
                                    ),
                                  );
                                  _refresh();
                                },
                                onLongPress: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Remover contato?'),
                                      content: Text('Remover ${c['name']}?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await LocalDb.removeContact(c['id']);
                                    _refresh();
                                  }
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6B21A8),
        child: const Icon(Icons.person_add, color: Colors.white),
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AddContactScreen()),
          );
          if (added == true) _refresh();
        },
      ),
    );
  }
}
