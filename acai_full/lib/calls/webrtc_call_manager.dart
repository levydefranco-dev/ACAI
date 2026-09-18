import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_signaling.dart';
import 'incoming_call_handler.dart';

/// Gerencia uma chamada WebRTC (áudio ou vídeo).
class WebRTCCallManager {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  String? myId;
  String? remoteId;
  bool isCaller = false;
  bool isVideo = false;

  final IncomingCallHandler callHandler;
  void Function()? onStateChanged;
  void Function(String status)? onStatus;

  WebRTCCallManager({required this.callHandler});

  static final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // Em produção adicione um TURN próprio:
      // {'urls': 'turn:turn.seudominio.com:3478', 'username': '...', 'credential': '...'},
    ]
  };

  Future<void> init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> dispose() async {
    await hangup(local: true);
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }

  Future<void> _createPeer() async {
    _pc = await createPeerConnection(_iceServers, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (myId != null && remoteId != null) {
        CallSignaling.send(
          fromId: myId!,
          toId: remoteId!,
          type: 'candidate',
          payload: candidate.toMap(),
        );
      }
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
        onStateChanged?.call();
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      onStatus?.call(state.toString());
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        callHandler.answer();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        hangup(local: false);
      }
      onStateChanged?.call();
    };
  }

  Future<void> _getUserMedia() async {
    final constraints = {
      'audio': true,
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': 640,
              'height': 480,
            }
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localRenderer.srcObject = _localStream;
    if (_pc != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
    }
    onStateChanged?.call();
  }

  /// Inicia chamada (lado que liga)
  Future<void> startCall({
    required String myId,
    required String toId,
    bool video = false,
  }) async {
    this.myId = myId;
    remoteId = toId;
    isCaller = true;
    isVideo = video;

    await _createPeer();
    await _getUserMedia();

    // Avisa o outro lado
    await CallSignaling.ring(myId: myId, toId: toId);
    await CallSignaling.send(
      fromId: myId,
      toId: toId,
      type: 'ring',
      payload: {'media': video ? 'video' : 'audio'},
    );

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': video ? 1 : 0,
    });
    await _pc!.setLocalDescription(offer);

    await CallSignaling.send(
      fromId: myId,
      toId: toId,
      type: 'offer',
      payload: {'sdp': offer.sdp, 'type': offer.type},
    );
    onStatus?.call('Chamando...');
  }

  /// Atende chamada (depois do PIN real)
  Future<void> acceptCall({
    required String myId,
    required String fromId,
    required Map<String, dynamic> offerPayload,
    bool video = false,
  }) async {
    this.myId = myId;
    remoteId = fromId;
    isCaller = false;
    isVideo = video;

    await _createPeer();
    await _getUserMedia();

    await _pc!.setRemoteDescription(RTCSessionDescription(
      offerPayload['sdp'],
      offerPayload['type'],
    ));

    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': video ? 1 : 0,
    });
    await _pc!.setLocalDescription(answer);

    await CallSignaling.send(
      fromId: myId,
      toId: fromId,
      type: 'answer',
      payload: {'sdp': answer.sdp, 'type': answer.type},
    );
    callHandler.answer();
    onStatus?.call('Conectado');
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    final type = signal['type'] as String?;
    final payload = signal['payload'];
    if (type == null) return;

    if (type == 'answer' && _pc != null && payload is Map) {
      await _pc!.setRemoteDescription(RTCSessionDescription(
        payload['sdp'],
        payload['type'],
      ));
      onStatus?.call('Conectado');
    }

    if (type == 'candidate' && _pc != null && payload is Map) {
      try {
        await _pc!.addCandidate(RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          payload['sdpMLineIndex'],
        ));
      } catch (_) {}
    }

    if (type == 'hangup') {
      await hangup(local: false);
    }
  }

  Future<void> hangup({bool local = true}) async {
    if (local && myId != null && remoteId != null) {
      await CallSignaling.hangup(myId: myId!, toId: remoteId!);
    }
    await _localStream?.dispose();
    _localStream = null;
    await _remoteStream?.dispose();
    _remoteStream = null;
    await _pc?.close();
    _pc = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    callHandler.reset();
    onStateChanged?.call();
  }

  void toggleMute() {
    final audioTracks = _localStream?.getAudioTracks() ?? [];
    for (final t in audioTracks) {
      t.enabled = !t.enabled;
    }
    onStateChanged?.call();
  }

  bool get isMuted {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return false;
    return !tracks.first.enabled;
  }
}
