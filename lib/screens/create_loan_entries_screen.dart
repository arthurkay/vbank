import 'package:flutter/material.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
import 'package:brick_core/query.dart';
import 'package:villagebanking/screens/create_loan_screen.dart';
import 'package:villagebanking/screens/create_loan_repayment_screen.dart';

class GroupMemberWithProfile {
  final GroupMember groupMember;
  final Profile profile;

  GroupMemberWithProfile({required this.groupMember, required this.profile});
}

class CreateLoanEntriesScreen extends StatefulWidget {
  final String groupId;

  const CreateLoanEntriesScreen({super.key, required this.groupId});

  @override
  State<CreateLoanEntriesScreen> createState() =>
      _CreateLoanEntriesScreenState();
}

class _CreateLoanEntriesScreenState extends State<CreateLoanEntriesScreen> {
  List<GroupMemberWithProfile> _groupMembersWithProfiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchGroupMembersWithProfiles();
  }

  Future<void> _fetchGroupMembersWithProfiles() async {
    try {
      final groupMembers = await Repository().get<GroupMember>(
        query: Query.where('groupId', widget.groupId),
      );

      final List<GroupMemberWithProfile> membersWithProfiles = [];
      for (final member in groupMembers) {
        final profiles = await Repository().get<Profile>(
          query: Query.where('id', member.memberId),
        );
        if (profiles.isNotEmpty) {
          membersWithProfiles.add(
            GroupMemberWithProfile(
              groupMember: member,
              profile: profiles.first,
            ),
          );
        }
      }

      setState(() {
        _groupMembersWithProfiles = membersWithProfiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading group members: $e')),
      );
    }
  }

  void _showActionBottomSheet(
    BuildContext context,
    String memberId,
    String memberName,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text('Create Loan for $memberName'),
                onTap: () {
                  Navigator.pop(context); // Close the bottom sheet
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateLoanScreen(
                        groupId: widget.groupId,
                        memberId: memberId,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                title: Text('Create Loan Repayment for $memberName'),
                onTap: () {
                  Navigator.pop(context); // Close the bottom sheet
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateLoanRepaymentScreen(
                        groupId: widget.groupId,
                        memberId: memberId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Members')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupMembersWithProfiles.isEmpty
          ? const Center(child: Text('No members found in this group.'))
          : ListView.builder(
              itemCount: _groupMembersWithProfiles.length,
              itemBuilder: (context, index) {
                final memberWithProfile = _groupMembersWithProfiles[index];
                return ListTile(
                  title: Text(memberWithProfile.profile.fullName),
                  subtitle: Text('Role: ${memberWithProfile.groupMember.role}'),
                  onTap: () => _showActionBottomSheet(
                    context,
                    memberWithProfile.groupMember.memberId,
                    memberWithProfile.profile.fullName,
                  ),
                );
              },
            ),
    );
  }
}
