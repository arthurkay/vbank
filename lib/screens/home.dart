import 'package:flutter/material.dart';
import 'package:villagebanking/main.dart' show supabase;
import 'package:villagebanking/screens/widgets/profile_content.dart';
import 'package:villagebanking/screens/widgets/group_content.dart';
import 'package:villagebanking/screens/widgets/home_content.dart';

class HomePageContainer extends StatefulWidget {
  const HomePageContainer({super.key});

  @override
  State<HomePageContainer> createState() => _HomePageContainerState();
}

class _HomePageContainerState extends State<HomePageContainer>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  // Content for the Home Page
  double _currentBalance = 1450.75;
  double _growthLevel = 0.78;
  // Mock Data for the Group Management Screen
  final List<Map<String, dynamic>> _groupMembers = [
    {
      'name': 'Kwesi Amoah',
      'contribution': 300,
      'loan': 500.0,
      'eligible': true,
      'next_repayment': '2025-11-01',
      'interest_rate': 0.05,
    },
    {
      'name': 'Aisha Juma',
      'contribution': 450,
      'loan': 0.0,
      'eligible': true,
      'next_repayment': 'N/A',
      'interest_rate': 0.05,
    },
    {
      'name': 'Thomas Osei',
      'contribution': 150,
      'loan': 1200.0,
      'eligible': false,
      'next_repayment': '2025-10-25',
      'interest_rate': 0.05,
    },
    {
      'name': 'Zara Hassan',
      'contribution': 200,
      'loan': 250.0,
      'eligible': true,
      'next_repayment': '2025-11-15',
      'interest_rate': 0.05,
    },
    {
      'name': 'Bayo Eze',
      'contribution': 600,
      'loan': 0.0,
      'eligible': true,
      'next_repayment': 'N/A',
      'interest_rate': 0.05,
    },
    {
      'name': 'Amara Okoro',
      'contribution': 50,
      'loan': 800.0,
      'eligible': false,
      'next_repayment': '2025-10-20',
      'interest_rate': 0.05,
    },
  ];

  final List<Map<String, String>> _communityFeed = [
    {'type': 'deposit', 'user': 'Aisha', 'amount': '50.00'},
    {
      'type': 'goal',
      'user': 'Your Group',
      'amount': 'Loan Pool Target Reached!',
    },
    {'type': 'praise', 'user': 'You', 'amount': 'Weekly commitment saved! ✨'},
    {
      'type': 'loan',
      'user': 'Kwesi',
      'amount': 'Loan disbursed for farm supplies',
    },
  ];
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _getScreenContent(int index) {
    switch (index) {
      case 0:
        return HomeContent(
          currentBalance: _currentBalance,
          growthLevel: _growthLevel,
          communityFeed: _communityFeed,
          animationController: _controller,
          membersCount: _groupMembers.length,
        );
      case 1:
        return GroupContent(groupMembers: _groupMembers);
      case 2:
        return const Center(
          child: Text(
            'Goals & Targets',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        );
      case 3:
        return ProfileContent(supabase);
      default:
        return const Center(child: Text('404 Screen Not Found'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine the title based on the selected index
    String screenTitle;
    switch (_selectedIndex) {
      case 1:
        screenTitle = 'Group Contributions';
        break;
      case 2:
        screenTitle = 'My Savings';
        break;
      case 3:
        screenTitle = 'Profile';
        break;
      default:
        screenTitle = 'The Growth Hub';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          screenTitle,
          style: TextStyle(
            color: theme.textTheme.titleLarge!.color,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        /* actions: [
          IconButton(
            icon: Icon(Icons.notifications_none, color: theme.iconTheme.color),
            onPressed: () {},
          ),
        ], */
      ),
      body: SafeArea(child: _getScreenContent(_selectedIndex)),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        elevation: 10,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_work_rounded),
            label: 'Group',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard_rounded),
            label: 'Savings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
