import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'facade/facade_screen.dart';
import 'calls/incoming_call_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
