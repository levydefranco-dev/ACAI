import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'facade/facade_screen.dart';
import 'calls/incoming_call_handler.dart';
import 'calls/incoming_call_service.dart';
import 'offline/offline_queue.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  OfflineQueue.startAutoRetry();

  runApp(const AcaiApp());
}

class AcaiApp extends StatefulWidget {
  const AcaiApp({super.key});

  @override
  State<AcaiApp> createState() => _AcaiAppState();
}

class _AcaiAppState extends State<AcaiApp> {
  @override
  void initState() {
    super.initState();
    // Inicia escuta de chamadas após o primeiro frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      IncomingCallService.start(navigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final callHandler = IncomingCallHandler();

    return MaterialApp(
      navigatorKey: navigatorKey,
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
