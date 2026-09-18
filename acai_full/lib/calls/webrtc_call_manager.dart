import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'call_signaling.dart';
import 'incoming_call_handler.dart';

class WebRTCCallManager {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

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

  static const iceUrl = 'https://www.ventureprojetos.com.br/app/api/ice.php';

  Future<void> init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await _loadIceServers();
  }

  /// Busca STUN/TURN no backend (Metered ou coturn configurado no config.php)
  Future<void> _loadIceServers() async {
    try {
      final res = await http.get(Uri.parse(iceUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final servers = data['iceServers'];
        if (servers is List && servers.isNotEmpty) {
          _iceConfig = {
            'iceServers': servers,
            'sdpSemantics': 'unified-plan',
          };
          debugPrint('AÇAI ICE source=${data['source']} servers=${servers.length}');
          onStatus?.call('TURN: ${data['source'] ?? 'ok'}');
          return;
        }
      }
    } catch (e) {
      debugPrint('AÇAI ICE fetch failed: $e — usando só STUN');
    }
    onStatus?.call('TURN: só STUN (configure ice.php)');
  }

  Future<void> dispose() async {
    await hangup(local: true);
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }

  Future<void> _createPeer() async {
    _pc = await createPeerConnection(_iceConfig);

    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      if (myId != null && remoteId != null) {
        CallSignaling.send(
          fromId: myId!,
          toId: remoteId!,
          type: 'candidate',
          payload: c.toMap(),
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

    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      onStatus?.call('ICE: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        onStatus?.call('Conectado');
        callHandler.answer();
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        onStatus?.call('Falha ICE — verifique TURN');
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      onStatus?.call('$state');
      onStateChanged?.call();
    };
  }

  Future<void> _getUserMedia() async {
    final constraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
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

  Future<void> startCall({
    required String myId,
    required String toId,
    bool video = false,
  }) async {
    this.myId = myId;
    remoteId = toId;
    isCaller = true;
    isVideo = video;

    onStatus?.call('Carregando TURN...');
    await _loadIceServers();
    onStatus?.call('Preparando...');
    await _createPeer();
    await _getUserMedia();

    await CallSignaling.send(
      fromId: myId,
      toId: toId,
      type: 'ring',
      payload: {'media': video ? 'video' : 'audio'},
    );

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': video,
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

    onStatus?.call('Carregando TURN...');
    await _loadIceServers();
    onStatus?.call('Atendendo...');
    await _createPeer();
    await _getUserMedia();

    await _pc!.setRemoteDescription(RTCSessionDescription(
      offerPayload['sdp'] as String?,
      offerPayload['type'] as String?,
    ));
    _remoteDescriptionSet = true;
    await _flushCandidates();

    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': video,
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

  Future<void> _flushCandidates() async {
    for (final c in _pendingCandidates) {
      try {
        await _pc?.addCandidate(c);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    final type = signal['type'] as String?;
    final payload = signal['payload'];
    if (type == null) return;

    if (type == 'answer' && _pc != null && payload is Map) {
      try {
        await _pc!.setRemoteDescription(RTCSessionDescription(
          payload['sdp'] as String?,
          payload['type'] as String?,
        ));
        _remoteDescriptionSet = true;
        await _flushCandidates();
        onStatus?.call('Conectado');
      } catch (e) {
        onStatus?.call('Erro answer: $e');
      }
    }

    if (type == 'candidate' && payload is Map) {
      final c = RTCIceCandidate(
        payload['candidate'] as String?,
        payload['sdpMid'] as String?,
        payload['sdpMLineIndex'] as int?,
      );
      if (_remoteDescriptionSet && _pc != null) {
        try {
          await _pc!.addCandidate(c);
        } catch (_) {}
      } else {
        _pendingCandidates.add(c);
      }
    }

    if (type == 'hangup') {
      await hangup(local: false);
    }
  }

  Future<void> hangup({bool local = true}) async {
    if (local && myId != null && remoteId != null) {
      await CallSignaling.hangup(myId: myId!, toId: remoteId!);
    }
    try { await _localStream?.dispose(); } catch (_) {}
    _localStream = null;
    try { await _remoteStream?.dispose(); } catch (_) {}
    _remoteStream = null;
    try { await _pc?.close(); } catch (_) {}
    _pc = null;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    callHandler.reset();
    onStateChanged?.call();
  }

  void toggleMute() {
    for (final t in _localStream?.getAudioTracks() ?? []) {
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
