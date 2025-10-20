import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/theme.dart';

class GroupMembersScreen extends StatelessWidget {
  const GroupMembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Members'),
      ),
      body: StreamBuilder<List<GroupMember>>(
        stream: Repository().subscribe<GroupMember>(),
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
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: growthAccent,
                    child: Text(member.role.substring(0, 1)),
                  ),
                  title: Text(member.memberId), // Replace with actual member name
                  subtitle: Text(member.role),
                  trailing: Text(member.status),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
