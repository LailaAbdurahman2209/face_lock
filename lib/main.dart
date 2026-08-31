import 'package:flutter/material.dart';

import 'screens/app_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FaceLockApp());
}

class FaceLockApp extends StatelessWidget {
  const FaceLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Lock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppGate(),
    );
  }
}
