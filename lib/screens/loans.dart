import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/loan.model.dart';
import 'package:villagebanking/brick/repository.dart';

import 'package:villagebanking/screens/widgets/loan_tile.dart';

class LoansScreen extends StatelessWidget {
  final String groupId;

  const LoansScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Loan>>(
        future: Repository().get<Loan>(
          query: Query.where('groupId', groupId),
          policy: OfflineFirstGetPolicy.alwaysHydrate,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No loans found.'));
          }

          final loans = snapshot.data!;

          return ListView.builder(
            itemCount: loans.length,
            itemBuilder: (context, index) {
              final loan = loans[index];
              return LoanTile(loan: loan);
            },
          );
        },
      ),
    );
  }
}
