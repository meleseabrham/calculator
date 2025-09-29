import 'package:flutter/material.dart';
import 'calculator_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6DFF6A),
          surface: Color(0xFF2F3A45),
          background: Color(0xFF2F3A45),
        ),
        scaffoldBackgroundColor: const Color(0xFF2F3A45),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const CalculatorPage(),
    );
  }
}
 
