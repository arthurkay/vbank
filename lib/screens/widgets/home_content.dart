import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:brick_core/core.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:villagebanking/brick/moodels/group.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/theme.dart';

import 'package:villagebanking/screens/activities.dart';
import 'package:villagebanking/screens/contributions.dart';
import 'package:villagebanking/screens/group_members.dart';
import 'package:villagebanking/screens/loans.dart';
import 'package:villagebanking/screens/loan_application.dart';
import 'package:villagebanking/screens/interest_calculator.dart';

class HomeContent extends StatelessWidget {
  final double currentBalance;
  final double growthLevel;
  final List<Map<String, String>> communityFeed;
  final AnimationController animationController;
  final int membersCount;
  final String? selectedGroupId;

  const HomeContent({
    required this.currentBalance,
    required this.growthLevel,
    required this.communityFeed,
    required this.animationController,
    required this.membersCount,
    this.selectedGroupId,
  });

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
        Color.lerp(growthAccent.withOpacity(0.3), growthAccent, growthLevel) ??
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
              query: selectedGroupId != null
                  ? Query(where: [Where.exact('id', selectedGroupId!)])
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
                            growthLevel < 0.3
                                ? Icons.eco_outlined
                                : growthLevel < 0.7
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
                      animation: animationController,
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
                              growthLevel < 0.3
                                  ? Icons.eco_outlined
                                  : growthLevel < 0.7
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
                                '${(growthLevel * 100).toInt()}%',
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
                      animation: animationController,
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
                              growthLevel < 0.3
                                  ? Icons.eco_outlined
                                  : growthLevel < 0.7
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
                                '${(growthLevel * 100).toInt()}%',
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

  // Helper method for the Community Feed (Engagement/Retention)
  Widget _buildCommunityFeed(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    final filteredCommunityFeed = selectedGroupId != null
        ? communityFeed.where((item) => item['group_id'] == selectedGroupId).toList()
        : communityFeed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 10.0),
          child: Text(
            'Community Feed (${membersCount} members)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.textTheme.titleLarge!.color,
            ),
          ),
        ),
        ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: filteredCommunityFeed.length,
          itemBuilder: (context, index) {
            final item = filteredCommunityFeed[index];
            IconData icon;
            Color color;
            String actionText;

            switch (item['type']) {
              case 'deposit':
                icon = Icons.savings;
                color = growthAccent;
                actionText = 'deposited \$${item['amount']}';
                break;
              case 'goal':
                icon = Icons.flag_rounded;
                color = Colors.orange;
                actionText = item['amount']!;
                break;
              case 'praise':
                icon = Icons.emoji_events;
                color = Colors.purple;
                actionText = item['amount']!;
                break;
              case 'loan':
                icon = Icons.handshake;
                color = Colors.blueGrey;
                actionText = item['amount']!;
                break;
              default:
                icon = Icons.info;
                color = Colors.grey;
                actionText = 'did something.';
            }

            return Container(
              margin: const EdgeInsets.only(
                bottom: 8.0,
                left: 16.0,
                right: 16.0,
              ),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF333333)
                      : const Color(0xFFE0E0E0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.cardColor,
                  child: Icon(icon, color: color),
                ),
                title: Text(
                  item['user']!,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.titleLarge!.color,
                  ),
                ),
                subtitle: Text(
                  actionText,
                  style: TextStyle(color: secondaryTextColor),
                ),
                trailing: Icon(Icons.chevron_right, color: secondaryTextColor),
              ),
            );
          },
        ),
      ],
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
                        builder: (context) => GroupMembersScreen(groupId: selectedGroupId),
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
                        builder: (context) => ActivitiesScreen(groupId: selectedGroupId),
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
