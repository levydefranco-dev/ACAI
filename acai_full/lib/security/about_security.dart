import 'package:flutter/material.dart';

class AboutSecurityScreen extends StatelessWidget {
  const AboutSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre a segurança'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(
          '''This camouflage hides the interface from someone looking at the screen quickly, but does not hide the application from a technical analysis of the phone (list of installed apps, data usage, forensic examination). Do not rely on this alone in a situation of search or seizure of the device.

Additional notes (AÇAI):
• Real PIN has no recovery. Use offline recovery phrase only.
• Duress PIN opens an empty app and can send a silent alert.
• Incoming calls open the facade. "Close" rejects the call. 5 taps + real PIN allows answering.
• Location is never collected unless you explicitly enable the security check-in.
• Server is zero-knowledge (only stores your ACAI-ID, version and last seen).
• No biometric unlock is allowed; any biometric attempt triggers duress mode.
• Updates are delivered in-app only while inside the real interface.
''',
          style: TextStyle(fontSize: 15, height: 1.55),
        ),
      ),
    );
  }
}
