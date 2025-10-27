import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:brick_core/core.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:villagebanking/brick/moodels/group.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/screens/interest_calculator.dart';
import 'package:villagebanking/theme.dart';

import 'package:villagebanking/screens/activities.dart';
import 'package:villagebanking/screens/contributions.dart';
import 'package:villagebanking/screens/group_members.dart';
import 'package:villagebanking/screens/loans.dart';
import 'package:villagebanking/screens/loan_application.dart';
import 'package:villagebanking/screens/add_user_to_group_screen.dart';
import 'package:villagebanking/screens/create_loan_entries_screen.dart';
import 'package:villagebanking/screens/create_user_screen.dart';

import 'package:villagebanking/main.dart' show supabase;
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:brick_core/query.dart';

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
      query: Query(where: [
        Where.exact('memberId', currentUserId),
        Where.exact('groupId', widget.selectedGroupId!),
      ]),
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

  // Helper method for the visually appealing "Growth Hub"
  Widget _buildGrowthHub(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final primaryTextColor = theme.textTheme.titleLarge!.color;
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    final LinearGradient soilGradient = LinearGradient(
      colors: isDarkMode
          ? [const Color(0xFF444444), const Color(0xFF1F1F1F)]
          : [const Color(0xFFCCCCCC), const Color(0xFFF7F7F7)],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    );

    final Color growthColor =
        Color.lerp(
          growthAccent.withOpacity(0.3),
          growthAccent,
          widget.growthLevel,
        ) ??
        growthAccent;

    return Container(
      padding: const EdgeInsets.all(24.0),
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.5)
                : Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Group Savings',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(Icons.visibility_off, color: secondaryTextColor),
            ],
          ),
          const SizedBox(height: 8.0),
          FutureBuilder(
            future: Repository().get<Group>(
              policy: OfflineFirstGetPolicy.alwaysHydrate,
              query: widget.selectedGroupId != null
                  ? Query(where: [Where.exact('id', widget.selectedGroupId)])
                  : Query(limit: 1),
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  width: 200.0,
                  height: 100.0,
                  child: Shimmer.fromColors(
                    baseColor: const Color.fromARGB(255, 167, 163, 163),
                    highlightColor: const Color.fromARGB(255, 59, 128, 255),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            widget.growthLevel < 0.3
                                ? Icons.eco_outlined
                                : widget.growthLevel < 0.7
                                ? Icons.scatter_plot_rounded
                                : Icons.trending_up,
                            color: Colors.white,
                            size: 40,
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: 25,
                              decoration: BoxDecoration(
                                gradient: soilGradient,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(50),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Text(
                              'Loading',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } else if (snapshot.hasError) {
                return Column(
                  children: [
                    AnimatedBuilder(
                      animation: widget.animationController,
                      builder: (context, child) {
                        return Text(
                          'Unable to load group data',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: primaryTextColor,
                            letterSpacing: -1.0,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20.0),
                    Center(
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [growthColor.withOpacity(0.7), growthColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: growthColor.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              widget.growthLevel < 0.3
                                  ? Icons.eco_outlined
                                  : widget.growthLevel < 0.7
                                  ? Icons.scatter_plot_rounded
                                  : Icons.trending_up,
                              color: Colors.white,
                              size: 40,
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 25,
                                decoration: BoxDecoration(
                                  gradient: soilGradient,
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(50),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Text(
                                '${(widget.growthLevel * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20.0),
                  ],
                );
              } else if (snapshot.hasData) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No data to show yet.'));
                }
                return Column(
                  children: [
                    AnimatedBuilder(
                      animation: widget.animationController,
                      builder: (context, child) {
                        return Text(
                          snapshot.data?.first.name ?? '',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: primaryTextColor,
                            letterSpacing: -1.0,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20.0),
                    Center(
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [growthColor.withOpacity(0.7), growthColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: growthColor.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              widget.growthLevel < 0.3
                                  ? Icons.eco_outlined
                                  : widget.growthLevel < 0.7
                                  ? Icons.scatter_plot_rounded
                                  : Icons.trending_up,
                              color: Colors.white,
                              size: 40,
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 25,
                                decoration: BoxDecoration(
                                  gradient: soilGradient,
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(50),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Text(
                                '${(widget.growthLevel * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20.0),
                  ],
                );
              } else {
                return const Center();
              }
            },
          ),
        ],
      ),
    );
  }

  // Helper method for transaction buttons
  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final buttonBorderColor = isDarkMode
        ? const Color(0xFF333333)
        : const Color(0xFFE0E0E0);
    final buttonBgColor = theme.cardColor;
    final textColor = theme.textTheme.bodyMedium!.color;

    Color iconColor = color == growthAccent ? growthAccent : textColor!;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 100,
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          decoration: BoxDecoration(
            color: buttonBgColor,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: buttonBorderColor),
            boxShadow: [
              BoxShadow(
                color: isDarkMode
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.02),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 30),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildGrowthHub(context),
          const SizedBox(height: 16.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.request_quote,
                  label: 'Loan Application',
                  color: Theme.of(context).textTheme.bodyMedium!.color!,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoanApplicationScreen(),
                      ),
                    );
                  },
                ),
                _buildActionButton(
                  context,
                  icon: Icons.calculate,
                  label: 'Interest Calculator',
                  color: Theme.of(context).textTheme.bodyMedium!.color!,
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
                _buildActionButton(
                  context,
                  icon: Icons.people,
                  label: 'Members',
                  color: Theme.of(context).textTheme.bodyMedium!.color!,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            GroupMembersScreen(groupId: widget.selectedGroupId),
                      ),
                    );
                  },
                ),
                _buildActionButton(
                  context,
                  icon: Icons.notifications,
                  label: 'Activities',
                  color: Theme.of(context).textTheme.bodyMedium!.color!,
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
                  _buildActionButton(
                    context,
                    icon: Icons.person_add,
                    label: 'Add User to Group',
                    color: Theme.of(context).textTheme.bodyMedium!.color!,
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
                  _buildActionButton(
                    context,
                    icon: Icons.person_add_alt_1,
                    label: 'Create User',
                    color: Theme.of(context).textTheme.bodyMedium!.color!,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreateUserScreen(),
                        ),
                      );
                    },
                  ),
                  _buildActionButton(
                    context,
                    icon: Icons.money,
                    label: 'Create Loan Entries',
                    color: Theme.of(context).textTheme.bodyMedium!.color!,
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
