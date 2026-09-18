import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart';
import '../home/home_screen.dart';

class SetupPinScreen extends StatefulWidget {
  const SetupPinScreen({super.key});

  @override
  State<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends State<SetupPinScreen> {
  final _realController = TextEditingController();
  final _confirmController = TextEditingController();
  final _duressController = TextEditingController();
  String _error = '';
  bool _loading = false;
  int _step = 1; // 1 = PIN real, 2 = confirmar, 3 = PIN coação (opcional)

  Future<void> _next() async {
    setState(() => _error = '');

    if (_step == 1) {
      final pin = _realController.text.trim();
      if (pin.length != 8) {
        setState(() => _error = 'O PIN deve ter exatamente 8 dígitos');
        return;
      }
      setState(() => _step = 2);
      return;
    }

    if (_step == 2) {
      if (_confirmController.text.trim() != _realController.text.trim()) {
        setState(() => _error = 'Os PINs não coincidem');
        return;
      }
      setState(() => _step = 3);
      return;
    }

    // Step 3 - finalizar
    setState(() => _loading = true);
    try {
      final duress = _duressController.text.trim();
      await AuthService.setupPins(
        realPin: _realController.text.trim(),
        duressPin: duress.isEmpty ? null : duress,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Senha configurada com sucesso'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
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
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Configurar acesso', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == 1) ...[
                const Text(
                  'Crie seu PIN real',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Este PIN abre o aplicativo normalmente.\nEle NÃO pode ser recuperado. Anote em local seguro.',
                  style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 32),
                _buildPinField(_realController, 'Digite 8 dígitos'),
              ],
              if (_step == 2) ...[
                const Text(
                  'Confirme o PIN real',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                _buildPinField(_confirmController, 'Digite novamente'),
              ],
              if (_step == 3) ...[
                const Text(
                  'PIN de coação (opcional)',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Se digitado sob pressão, o app abre vazio e pode enviar alerta silencioso.\nDeixe em branco se não quiser usar.',
                  style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 32),
                _buildPinField(_duressController, '8 dígitos ou deixe vazio'),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(_error, style: const TextStyle(color: Colors.redAccent)),
              ],
              const Spacer(),
              ElevatedButton(
                onPressed: _loading ? null : _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_step == 3 ? 'Concluir' : 'Continuar'),
              ),
              if (_step == 3)
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          _duressController.clear();
                          _next();
                        },
                  child: const Text('Pular PIN de coação', style: TextStyle(color: Colors.white54)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 8,
      style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 8),
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 16, letterSpacing: 1),
        counterText: '',
        border: const OutlineInputBorder(),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.purpleAccent),
        ),
      ),
      onSubmitted: (_) => _next(),
    );
  }
}
