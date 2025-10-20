import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/contribution.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:intl/intl.dart';
import 'package:brick_core/query.dart';

class ContributionsScreen extends StatelessWidget {
  final String? groupId;

  const ContributionsScreen({super.key, this.groupId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Contribution>>(
        stream: Repository().subscribe<Contribution>(
          query: groupId != null ? Query.where('groupId', groupId!) : null,
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
                  subtitle: Text(
                    'Member: ${contribution.memberId}',
                  ), // Replace with actual member name
                  trailing: Text(
                    DateFormat.yMd().format(contribution.transactionDate),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
