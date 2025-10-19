import 'package:flutter/material.dart';
import 'package:villagebanking/theme.dart';

class GroupContent extends StatelessWidget {
  final List<Map<String, dynamic>> groupMembers;

  const GroupContent({required this.groupMembers});

  // Calculate projected interest based on mock data
  String _calculateInterest(double loanAmount, double rate) {
    if (loanAmount <= 0) return 'N/A';
    // Simplified calculation: Monthly interest (Loan * Rate / 12)
    final interest = loanAmount * (rate / 12);
    return '\$${interest.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(context, secondaryTextColor!),
          const SizedBox(height: 16.0),
          Text(
            'Member Financial Health',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.textTheme.titleLarge!.color,
            ),
          ),
          const SizedBox(height: 10.0),
          ...groupMembers
              .map(
                (member) =>
                    _buildMemberCard(context, member, secondaryTextColor),
              )
              .toList(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, Color secondaryTextColor) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final totalContributions = groupMembers.fold(
      0.0,
      (sum, item) => sum + item['contribution'],
    );
    final totalLoans = groupMembers.fold(
      0.0,
      (sum, item) => sum + item['loan'],
    );
    final eligibleCount = groupMembers
        .where((m) => m['eligible'] == true)
        .length;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem(
            'Total Contributions',
            '\$${totalContributions.toStringAsFixed(2)}',
            theme.textTheme.titleLarge!.color!,
          ),
          _summaryItem(
            'Outstanding Loans',
            '\$${totalLoans.toStringAsFixed(2)}',
            theme.textTheme.titleLarge!.color!,
          ),
          _summaryItem(
            'Loan Eligible',
            '${eligibleCount}/${groupMembers.length}',
            growthAccent,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMemberCard(
    BuildContext context,
    Map<String, dynamic> member,
    Color secondaryTextColor,
  ) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final hasLoan = member['loan'] > 0;
    final eligibilityColor = member['eligible'] ? growthAccent : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            member['name'],
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: theme.textTheme.titleLarge!.color,
            ),
          ),
          Divider(
            height: 16,
            thickness: 1,
            color: isDarkMode
                ? const Color(0xFF333333)
                : const Color(0xFFE0E0E0),
          ),
          _infoRow(
            'Monthly Contribution',
            '\$${member['contribution'].toStringAsFixed(2)}',
            growthAccent,
            secondaryTextColor,
          ),
          _infoRow(
            'Current Loan Balance',
            hasLoan ? '\$${member['loan'].toStringAsFixed(2)}' : 'None',
            hasLoan ? Colors.red.shade700 : growthAccent,
            secondaryTextColor,
          ),
          _infoRow(
            'Next Repayment Due',
            member['next_repayment'],
            hasLoan ? Colors.orange : secondaryTextColor!,
            secondaryTextColor,
          ),
          _infoRow(
            'Projected Interest',
            _calculateInterest(member['loan'], member['interest_rate']),
            Colors.grey,
            secondaryTextColor,
          ),
          const SizedBox(height: 10),
          _eligibilityPill(member['eligible'], eligibilityColor),
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value,
    Color valueColor,
    Color secondaryTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: secondaryTextColor, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eligibilityPill(bool eligible, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        eligible ? 'Eligible for New Loan' : 'Loan In Progress',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
