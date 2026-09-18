import 'package:flutter/foundation.dart';

enum CallState { ringing, answered, rejected, missed, duress }

class IncomingCallHandler extends ChangeNotifier {
  CallState _state = CallState.ringing;
  String? callerId;
  DateTime? startedAt;
  static const timeoutSeconds = 40;

  CallState get state => _state;

  void startIncoming({required String fromId}) {
    callerId = fromId;
    startedAt = DateTime.now();
    _state = CallState.ringing;
    notifyListeners();

    Future.delayed(const Duration(seconds: timeoutSeconds), () {
      if (_state == CallState.ringing) {
        _state = CallState.missed;
        notifyListeners();
      }
    });
  }

  void rejectFromFacade() {
    if (_state == CallState.ringing) {
      _state = CallState.rejected;
      notifyListeners();
    }
  }

  void authenticatedReal() {
    if (_state == CallState.ringing) {
      notifyListeners();
    }
  }

  void authenticatedDuress() {
    if (_state == CallState.ringing) {
      _state = CallState.duress;
      notifyListeners();
    }
  }

  void answer() {
    if (_state == CallState.ringing) {
      _state = CallState.answered;
      notifyListeners();
    }
  }

  void reset() {
    _state = CallState.ringing;
    callerId = null;
    startedAt = null;
  }
}
