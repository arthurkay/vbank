import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:villagebanking/brick/moodels/activity.model.dart';
import 'package:villagebanking/brick/moodels/contribution.model.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/moodels/group.model.dart';
import 'package:villagebanking/brick/moodels/loan_repayment.model.dart';
import 'package:villagebanking/brick/moodels/loan.model.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
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
  await _syncRemoteDeletions();
  runApp(const VillageBankingApp());
}

Future<void> _syncRemoteDeletions() async {
  await Repository().destructiveLocalSyncFromRemote<Group>();
  await Repository().destructiveLocalSyncFromRemote<Profile>();
  await Repository().destructiveLocalSyncFromRemote<GroupMember>();
  await Repository().destructiveLocalSyncFromRemote<Contribution>();
  await Repository().destructiveLocalSyncFromRemote<Loan>();
  await Repository().destructiveLocalSyncFromRemote<LoanRepayment>();
  await Repository().destructiveLocalSyncFromRemote<Activity>();
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
