import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/screens/home.dart';
import 'package:villagebanking/screens/login.dart';
import 'package:villagebanking/theme.dart';

late Supabase supabase;
void main() async {
  await dotenv.load(fileName: ".env");
  supabase = await Supabase.initialize(
    url: dotenv.get("URL"),
    anonKey: dotenv.get("ANON_KEY"),
  );
  await Repository.configure(databaseFactory);
  await Repository().initialize();
  runApp(const VillageBankingApp());
}

class VillageBankingApp extends StatelessWidget {
  const VillageBankingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Growth Hub',
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ThemeMode.system,
      home: const AuthGate(), // Start with the Auth Gate
    );
  }
}

// --- Auth Gate (Decides which screen to show) ---
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Mock authentication state
  bool _isLoggedIn = supabase.client.auth.currentSession != null ? true : false;

  void _handleLogin(bool success) {
    if (success) {
      setState(() {
        _isLoggedIn = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn) {
      return const HomePageContainer();
    } else {
      return LoginScreen(onLoginSuccess: () => _handleLogin(true));
    }
  }
}
