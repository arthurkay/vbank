import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/main.dart' show supabase;
import 'package:villagebanking/screens/widgets/profile_content.dart';
import 'package:villagebanking/screens/widgets/home_content.dart';
import 'package:villagebanking/screens/loans.dart';
import 'package:villagebanking/screens/contributions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brick_core/query.dart';
import 'package:villagebanking/brick/moodels/group.model.dart';

import 'package:villagebanking/brick/repository.dart';

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

  late AnimationController _controller;

  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _loadSelectedGroup();
  }

  Future<void> _loadSelectedGroup() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedGroupId = prefs.getString('selectedGroupId');
    });
  }

  Future<void> _showGroupSelector(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = supabase.client.auth.currentUser?.id;

    if (currentUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not logged in')));
      return;
    }

    final groupMemberships = await Repository().get<GroupMember>(
      query: Query.where('memberId', currentUserId),
      policy: OfflineFirstGetPolicy.alwaysHydrate,
    );

    final groups = <Group>[];
    for (final membership in groupMemberships) {
      final group = await Repository().get<Group>(
        query: Query.where('id', membership.groupId),
      );
      if (group.isNotEmpty) {
        groups.add(group.first);
      }
    }

    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No groups found for this user')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Select Group',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return Card(
                      child: ListTile(
                        title: Text(group.name),
                        onTap: () async {
                          await prefs.setString('selectedGroupId', group.id);
                          setState(() {
                            _selectedGroupId = group.id;
                          });
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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
          communityFeed: [],
          animationController: _controller,
          membersCount: 0,
          selectedGroupId: _selectedGroupId,
        );
      case 1:
        return const ContributionsScreen();
      case 2:
        return LoansScreen(groupId: _selectedGroupId ?? "0");
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
        screenTitle = 'Contributions';
        break;
      case 2:
        screenTitle = 'Loans';
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
        actions: [
          IconButton(
            icon: Icon(Icons.swap_vert, color: theme.iconTheme.color),
            onPressed: () => _showGroupSelector(context),
          ),
        ],
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
            icon: Icon(Icons.attach_money),
            label: 'Contributions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Loans',
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
