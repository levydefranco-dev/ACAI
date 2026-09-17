import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'facade/facade_screen.dart';
import 'calls/incoming_call_handler.dart';
import 'auth/auth_service.dart';
import 'auth/setup_pin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Deixa a barra de status transparente para a fachada ficar full-screen
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const AcaiApp());
}

class AcaiApp extends StatelessWidget {
  const AcaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final callHandler = IncomingCallHandler();

    return MaterialApp(
      title: 'Açaí',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: FacadeScreen(callHandler: callHandler),
    );
  }
}
