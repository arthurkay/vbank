import 'package:brick_core/core.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/screens/widgets/group_member_tile.dart';
import 'package:villagebanking/theme.dart';

class GroupMembersScreen extends StatelessWidget {
  final String? groupId;

  const GroupMembersScreen({super.key, this.groupId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Members')),
      body: StreamBuilder<List<GroupMember>>(
        stream: Repository().subscribe<GroupMember>(
          policy: OfflineFirstGetPolicy.alwaysHydrate,
          query: groupId != null ? Query.where('groupId', groupId!) : null,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No members found.'));
          }

          final members = snapshot.data!;

          return ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              return GroupMemberTile(groupMember: member);
            },
          );
        },
      ),
    );
  }
}
