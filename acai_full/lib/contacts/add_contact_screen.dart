import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../storage/local_db.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String _error = '';
  bool _loading = false;

  Future<void> _save() async {
    final id = _idController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (!id.startsWith('ACAI-') || id.length < 14) {
      setState(() => _error = 'ID inválido. Formato: ACAI-XXXX-XXXX-XXXX');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Digite um nome para o contato');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      await LocalDb.addContact(id: id, displayName: name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contato adicionado'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true); // retorna true = atualizar lista
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar contato'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Adicione apenas pessoas do seu grupo de confiança.\nO compartilhamento do ID deve ser feito por canal seguro.',
              style: TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _idController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'ID do contato',
                hintText: 'ACAI-XXXX-XXXX-XXXX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome (só para você)',
                hintText: 'Ex: Maria, João...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(_error, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B21A8),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
              ),
              child: _loading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
  }
}
