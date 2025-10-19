import 'package:brick_core/query.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/main.dart';
import 'package:villagebanking/theme.dart';

class ProfileContent extends StatelessWidget {
  final Supabase supabase;
  const ProfileContent(this.supabase, {super.key});

  Widget _buildProfileTile(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) Icon(icon, color: growthAccent, size: 24),
          if (icon != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? theme.textTheme.titleLarge!.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryTextColor = theme.textTheme.titleLarge!.color;
    final Map<String, dynamic> _mockUserProfile = {
      'id': supabase.client.auth.currentUser?.id,
      'name': supabase.client.auth.currentUser?.userMetadata?['full_name'],
      'group_role': 'Treasurer/Admin',
      'email': supabase.client.auth.currentUser?.email,
      'phone': '+260 971 123 456',
      'group_name': 'Zambia Copper Savings Group',
      'joining_date': supabase.client.auth.currentUser?.createdAt,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User Header and Avatar
          Center(
            child: FutureBuilder(
              future: Repository().get<Profile>(query: Query(limit: 1)),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                } else if (snapshot.hasData) {
                  var userData = snapshot.data!.first;
                  return Column(
                    children: [
                      const CircleAvatar(
                        radius: 40,
                        backgroundColor: growthAccent,
                        child: Icon(Icons.person, color: darkText, size: 40),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        userData.fullName ?? "N/A",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userData.isAdmin ? 'Admin' : 'Member',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          ),
          const SizedBox(height: 30),

          // Profile Details Section
          Text(
            'Account Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 12),
          _buildProfileTile(
            context,
            label: 'Group Name',
            value: _mockUserProfile['group_name'],
            icon: Icons.groups_2_rounded,
          ),
          _buildProfileTile(
            context,
            label: 'Email Address',
            value: _mockUserProfile['email'],
            icon: Icons.email_outlined,
          ),
          _buildProfileTile(
            context,
            label: 'Phone Number',
            value: _mockUserProfile['phone'],
            icon: Icons.phone_outlined,
          ),
          _buildProfileTile(
            context,
            label: 'Joined Date',
            value: _mockUserProfile['joining_date'],
            icon: Icons.calendar_month_outlined,
          ),

          const SizedBox(height: 30),

          /*          // Settings Section
          Text(
            'Settings & Support',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingsItem(
            context,
            title: 'Security & Privacy',
            icon: Icons.security_rounded,
          ),
          _buildSettingsItem(
            context,
            title: 'Help & FAQ',
            icon: Icons.help_outline,
          ),
 */
          const SizedBox(height: 30),

          // Logout Button
          ElevatedButton.icon(
            onPressed: () async {
              // Simulate a confirmation dialog before logging out
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Logging you out...'),
                  backgroundColor: Colors.red.shade700,
                  duration: const Duration(seconds: 4),
                ),
              );
              await supabase.client.auth.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const AuthGate()),
                (Route<dynamic> route) => false,
              );
            },
            icon: const Icon(Icons.logout, color: darkText),
            label: const Text(
              'Log Out',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: darkText,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
