import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/main.dart';
import 'package:villagebanking/screens/activities.dart';
import 'package:villagebanking/screens/add_user_to_group_screen.dart';
import 'package:villagebanking/screens/create_loan_entries_screen.dart';
import 'package:villagebanking/screens/create_user_screen.dart';
import 'package:villagebanking/screens/group_members.dart';
import 'package:villagebanking/screens/interest_calculator.dart';
import 'package:villagebanking/screens/loan_application.dart';
import 'package:villagebanking/screens/widgets/action_button.dart';
import 'package:villagebanking/screens/widgets/growth_hub.dart';

class HomeContent extends StatefulWidget {
  final double currentBalance;
  final double growthLevel;
  final List<Map<String, String>> communityFeed;
  final AnimationController animationController;

  final int membersCount;
  final String? selectedGroupId;

  const HomeContent({
    super.key,
    required this.currentBalance,
    required this.growthLevel,
    required this.communityFeed,
    required this.animationController,
    required this.membersCount,
    this.selectedGroupId,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  @override
  void didUpdateWidget(covariant HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedGroupId != oldWidget.selectedGroupId) {
      _checkAdminStatus();
    }
  }

  Future<void> _checkAdminStatus() async {
    debugPrint("This doesnt work ${widget.selectedGroupId}");
    if (widget.selectedGroupId == null) {
      setState(() {
        _isAdmin = false;
      });
      return;
    }

    final currentUserId = supabase.client.auth.currentUser?.id;
    if (currentUserId == null) {
      setState(() {
        _isAdmin = false;
      });
      return;
    }

    final groupMemberships = await Repository().get<GroupMember>(
      query: Query(
        where: [
          Where.exact('memberId', currentUserId),
          Where.exact('groupId', widget.selectedGroupId!),
        ],
      ),
    );

    if (groupMemberships.isNotEmpty) {
      setState(() {
        _isAdmin = groupMemberships.first.role == 'Admin';
      });
    } else {
      setState(() {
        _isAdmin = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GrowthHub(
            growthLevel: widget.growthLevel,
            selectedGroupId: widget.selectedGroupId,
            animationController: widget.animationController,
          ),
          const SizedBox(height: 16.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                ActionButton(
                  icon: Icons.request_quote,
                  label: 'Loan Application',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoanApplicationScreen(),
                      ),
                    );
                  },
                ),
                ActionButton(
                  icon: Icons.calculate,
                  label: 'Interest Calculator',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const InterestCalculatorScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                ActionButton(
                  icon: Icons.people,
                  label: 'Members',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            GroupMembersScreen(groupId: widget.selectedGroupId ?? "s"),
                      ),
                    );
                  },
                ),
                ActionButton(
                  icon: Icons.notifications,
                  label: 'Activities',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ActivitiesScreen(groupId: widget.selectedGroupId),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  ActionButton(
                    icon: Icons.person_add,
                    label: 'Add User to Group',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddUserToGroupScreen(
                            groupId: widget.selectedGroupId!,
                          ),
                        ),
                      );
                    },
                  ),
                  ActionButton(
                    icon: Icons.person_add_alt_1,
                    label: 'Create User',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreateUserScreen(),
                        ),
                      );
                    },
                  ),
                  ActionButton(
                    icon: Icons.money,
                    label: 'Create Loan Entries',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateLoanEntriesScreen(
                            groupId: widget.selectedGroupId!,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
