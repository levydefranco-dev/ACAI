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
  static const secretZone = Rect.fromLTWH(20, 60, 120, 120);

  void _handleTap(TapDownDetails details) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds > 900) {
      _tapCount = 0;
    }
    _lastTap = now;

    if (secretZone.contains(details.localPosition)) {
      setState(() => _tapCount++);
      if (_tapCount >= 5) {
        _tapCount = 0;
        _openPinScreen();
      }
    } else {
      _tapCount = 0;
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

    return Scaffold(
      body: GestureDetector(
        onTapDown: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/acai_facade_banner.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF6B21A8),
                child: const Center(
                  child: Text('AÇAÍ', style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                  onPressed: _onClosePressed,
                ),
              ),
            ),
            if (isRinging)
              const Positioned(
                bottom: 12,
                right: 12,
                child: Opacity(
                  opacity: 0.15,
                  child: Icon(Icons.circle, size: 8, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
