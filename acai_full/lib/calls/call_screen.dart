import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'webrtc_call_manager.dart';

class CallScreen extends StatefulWidget {
  final WebRTCCallManager manager;
  final String contactName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.manager,
    required this.contactName,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String _status = 'Conectando...';

  @override
  void initState() {
    super.initState();
    widget.manager.onStateChanged = () {
      if (mounted) setState(() {});
    };
    widget.manager.onStatus = (s) {
      if (mounted) setState(() => _status = s);
    };
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Vídeo remoto (tela cheia)
            if (m.isVideo)
              Positioned.fill(
                child: RTCVideoView(
                  m.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              const Center(
                child: Icon(Icons.person, size: 120, color: Colors.white24),
              ),

            // Vídeo local (pip)
            if (m.isVideo)
              Positioned(
                top: 16,
                right: 16,
                width: 110,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    m.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

            // Info
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    widget.contactName,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),

            // Controles
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundBtn(
                    icon: m.isMuted ? Icons.mic_off : Icons.mic,
                    color: m.isMuted ? Colors.white24 : Colors.white12,
                    onTap: () {
                      m.toggleMute();
                      setState(() {});
                    },
                  ),
                  _roundBtn(
                    icon: Icons.call_end,
                    color: Colors.red,
                    size: 68,
                    onTap: () async {
                      await m.hangup();
                      if (mounted) Navigator.of(context).pop();
                    },
                  ),
                  _roundBtn(
                    icon: Icons.cameraswitch,
                    color: Colors.white12,
                    onTap: () {
                      // switch camera - opcional
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 56,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.45),
        ),
      ),
    );
  }
}
