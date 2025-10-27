import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:brick_core/query.dart';
import 'package:villagebanking/screens/create_loan_repayment_screen.dart';
import 'package:villagebanking/theme.dart';

class GroupMemberTile extends StatelessWidget {
  final GroupMember groupMember;

  const GroupMemberTile({super.key, required this.groupMember});

  Future<Profile?> _getProfile(String memberId) async {
    final profiles = await Repository().get<Profile>(
      query: Query.where('id', memberId, limit1: true),
    );
    return profiles.isNotEmpty ? profiles.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: growthAccent,
          child: Text(groupMember.role.substring(0, 1)),
        ),
        title: FutureBuilder<Profile?>(
          future: _getProfile(groupMember.memberId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Loading...');
            }
            if (snapshot.hasError) {
              return const Text('Error');
            }
            if (snapshot.hasData && snapshot.data != null) {
              return Text(snapshot.data!.fullName ?? 'N/A');
            }
            return const Text('Unknown');
          },
        ),
        subtitle: Text(groupMember.role),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(groupMember.status),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CreateLoanRepaymentScreen(
                      groupId: groupMember.groupId,
                      memberId: groupMember.memberId,
                    ),
                  ),
                );
              },
              child: const Text('Repay Loan'),
            ),
          ],
        ),
      ),
    );
  }
}
