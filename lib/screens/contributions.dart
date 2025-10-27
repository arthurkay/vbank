import 'package:brick_core/query.dart';
import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/contribution.model.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:intl/intl.dart';
import 'package:villagebanking/main.dart';

import 'create_contribution_screen.dart';

class ContributionsScreen extends StatefulWidget {
  final String groupId;

  const ContributionsScreen({super.key, required this.groupId});

  @override
  State<ContributionsScreen> createState() => _ContributionsScreenState();
}

class _ContributionsScreenState extends State<ContributionsScreen> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  @override
  void didUpdateWidget(covariant ContributionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groupId != oldWidget.groupId) {
      _checkAdminStatus();
    }
  }

  Future<void> _checkAdminStatus() async {
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
          Where.exact("groupId", widget.groupId!),
          Where.exact("memberId", currentUserId),
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
    return Scaffold(
      body: StreamBuilder<List<Contribution>>(
        stream: Repository().subscribe<Contribution>(
          query: Query.where('groupId', widget.groupId),
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No contributions found.'));
          }

          final contributions = snapshot.data!;

          return ListView.builder(
            itemCount: contributions.length,
            itemBuilder: (context, index) {
              final contribution = contributions[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: Text('Amount: ${contribution.amount}'),
                  subtitle: _MemberName(memberId: contribution.memberId),
                  trailing: Text(
                    DateFormat.yMd().format(contribution.transactionDate),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CreateContributionScreen(groupId: widget.groupId!),
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _MemberName extends StatelessWidget {
  final String memberId;

  const _MemberName({required this.memberId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Profile>>(
      future: Repository().get<Profile>(query: Query.where('id', memberId)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return Text('Member: ${snapshot.data!.first.fullName}');
        } else {
          return const Text('Member: Unknown');
        }
      },
    );
  }
}
