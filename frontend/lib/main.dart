import 'package:flutter/material.dart';

import 'screens/map_screen.dart';

void main() {
  runApp(const SmartNavApp());
}

class SmartNavApp extends StatelessWidget {
  const SmartNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '適應型智慧旅遊導航',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
