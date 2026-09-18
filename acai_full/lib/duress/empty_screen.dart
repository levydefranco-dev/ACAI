import 'package:flutter/material.dart';
import '../facade/facade_screen.dart';

/// Tela que aparece quando o PIN de coação é digitado.
/// Parece um app recém-instalado, sem contatos nem histórico.
class EmptyDuressScreen extends StatelessWidget {
  const EmptyDuressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Açaí'),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const FacadeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey),
              SizedBox(height: 24),
              Text(
                'Nenhuma conversa',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'Adicione contatos para começar',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
