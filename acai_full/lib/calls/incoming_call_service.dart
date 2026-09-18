import 'package:flutter/material.dart';
import '../storage/local_db.dart';
import 'call_signaling.dart';
import 'incoming_call_handler.dart';
import 'webrtc_call_manager.dart';
import 'call_screen.dart';
import '../facade/facade_screen.dart';
import '../auth/pin_entry_screen.dart';

/// Escuta sinais de chamada em background e aplica o fluxo de fachada.
class IncomingCallService {
  static final IncomingCallHandler handler = IncomingCallHandler();
  static WebRTCCallManager? pendingManager;
  static Map<String, dynamic>? pendingOffer;
  static String? pendingFromId;
  static bool _listening = false;

  static Future<void> start(GlobalKey<NavigatorState> navKey) async {
    if (_listening) return;
    final myId = await LocalDb.getMyId();
    if (myId == null) return;

    CallSignaling.onSignal = (signal) async {
      final type = signal['type'] as String?;
      final fromId = signal['from_id'] as String?;
      if (type == null || fromId == null) return;

      if (type == 'ring' || type == 'offer') {
        pendingFromId = fromId;
        if (type == 'offer') {
          pendingOffer = Map<String, dynamic>.from(signal['payload'] ?? {});
        }
        handler.startIncoming(fromId: fromId);

        // Sobe a fachada (camuflagem)
        final ctx = navKey.currentContext;
        if (ctx != null) {
          Navigator.of(ctx).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => FacadeScreen(
                callHandler: handler,
                onAuthenticatedForCall: (isReal) async {
                  if (isReal && pendingFromId != null) {
                    // PIN real → atende
                    await _acceptCall(ctx, myId);
                  } else {
                    // Coação ou rejeição
                    handler.rejectFromFacade();
                    if (pendingFromId != null) {
                      CallSignaling.hangup(myId: myId, toId: pendingFromId!);
                    }
                    pendingFromId = null;
                    pendingOffer = null;
                  }
                },
              ),
            ),
            (route) => false,
          );
        }
      }

      if (type == 'hangup') {
        handler.reset();
        pendingFromId = null;
        pendingOffer = null;
      }

      // Encaminha ICE/answer se já estiver em chamada
      pendingManager?.handleSignal(signal);
    };

    CallSignaling.startListening(myId);
    _listening = true;
  }

  static Future<void> _acceptCall(BuildContext context, String myId) async {
    if (pendingFromId == null) return;

    final manager = WebRTCCallManager(callHandler: handler);
    await manager.init();
    pendingManager = manager;

    // Se ainda não temos o offer, espera um pouco
    if (pendingOffer == null) {
      await Future.delayed(const Duration(seconds: 2));
    }

    if (pendingOffer != null) {
      await manager.acceptCall(
        myId: myId,
        fromId: pendingFromId!,
        offerPayload: pendingOffer!,
        video: false,
      );
    }

    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            manager: manager,
            contactName: pendingFromId ?? 'Chamada',
            isIncoming: true,
          ),
        ),
      );
    }
  }
}
