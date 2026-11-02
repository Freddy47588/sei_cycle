import 'package:flutter/material.dart';

import '../features/auth/screen/auth_gate.dart';
import '../theme/app_theme.dart';

class SeiCycleApp extends StatelessWidget {
  const SeiCycleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeiCycle',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}
