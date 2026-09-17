import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart';
import 'setup_pin_screen.dart';

class PinEntryScreen extends StatefulWidget {
  final void Function(bool isRealPin)? onAuthenticated;
  const PinEntryScreen({super.key, this.onAuthenticated});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _controller = TextEditingController();
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final setup = await AuthService.isSetupComplete();
    if (!setup && mounted) {
      // Primeira vez → vai para tela de configuração
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupPinScreen()),
      );
    }
  }

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (pin.length != 8) {
      setState(() => _error = 'Digite 8 dígitos');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await AuthService.authenticate(pin);

    if (!mounted) return;

    setState(() => _loading = false);

    switch (result) {
      case AuthResult.real:
        widget.onAuthenticated?.call(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acesso liberado'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(); // volta para a fachada ou vai para home real
        // TODO: navegar para a tela principal do app (conversas)
        break;

      case AuthResult.duress:
        widget.onAuthenticated?.call(false);
        // Entra no modo vazio (sem indicar que é coação)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acesso liberado')),
        );
        Navigator.of(context).pop();
        // TODO: abrir modo vazio
        break;

      case AuthResult.needsSetup:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SetupPinScreen()),
        );
        break;

      case AuthResult.fail:
        setState(() => _error = 'Código incorreto');
        _controller.clear();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Digite o código',
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 8),
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.purpleAccent),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
