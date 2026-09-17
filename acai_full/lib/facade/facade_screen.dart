import 'package:flutter/material.dart';
import '../auth/pin_entry_screen.dart';
import '../calls/incoming_call_handler.dart';

class FacadeScreen extends StatefulWidget {
  final IncomingCallHandler? callHandler;
  const FacadeScreen({super.key, this.callHandler});

  @override
  State<FacadeScreen> createState() => _FacadeScreenState();
}

class _FacadeScreenState extends State<FacadeScreen> {
  int _tapCount = 0;
  DateTime? _lastTap;

  // Área secreta (canto superior esquerdo)
  static const double secretLeft = 0;
  static const double secretTop = 0;
  static const double secretWidth = 160;
  static const double secretHeight = 180;

  void _handleTap(TapDownDetails details) {
    final pos = details.localPosition;
    final now = DateTime.now();

    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds > 1200) {
      _tapCount = 0;
    }
    _lastTap = now;

    final inSecretZone = pos.dx >= secretLeft &&
        pos.dx <= secretLeft + secretWidth &&
        pos.dy >= secretTop &&
        pos.dy <= secretTop + secretHeight;

    if (inSecretZone) {
      setState(() => _tapCount++);
      if (_tapCount >= 5) {
        _tapCount = 0;
        _openPinScreen();
      }
    } else {
      if (_tapCount > 0) setState(() => _tapCount = 0);
    }
  }

  void _openPinScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PinEntryScreen(
          onAuthenticated: (isReal) {
            if (widget.callHandler != null) {
              if (isReal) {
                widget.callHandler!.authenticatedReal();
              } else {
                widget.callHandler!.authenticatedDuress();
              }
            }
          },
        ),
      ),
    );
  }

  void _onClosePressed() {
    if (widget.callHandler != null &&
        widget.callHandler!.state == CallState.ringing) {
      widget.callHandler!.rejectFromFacade();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRinging = widget.callHandler?.state == CallState.ringing;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF6B21A8),
      body: GestureDetector(
        onTapDown: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Banner ajustado ao tamanho da tela
              Image.asset(
                'assets/images/acai_facade_banner.jpg',
                fit: BoxFit.cover,          // preenche a tela inteira
                width: size.width,
                height: size.height,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF6B21A8),
                  child: const Center(
                    child: Text(
                      'AÇAÍ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

              // Botão Fechar visível
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 16,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _onClosePressed,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, color: Colors.white, size: 22),
                          SizedBox(width: 4),
                          Text(
                            'Fechar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              if (isRinging)
                const Positioned(
                  bottom: 16,
                  right: 16,
                  child: Opacity(
                    opacity: 0.12,
                    child: Icon(Icons.circle, size: 10, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
