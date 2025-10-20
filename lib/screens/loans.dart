import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/loan.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:intl/intl.dart';

class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Loan>>(
        stream: Repository().subscribe<Loan>(),
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
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.monetization_on),
                  title: Text('Amount: ${loan.principalAmount}'),
                  subtitle: Text(
                    'Member: ${loan.memberId}',
                  ), // Replace with actual member name
                  trailing: Text(loan.status),
                  onTap: () {
                    // Navigate to LoanRepaymentsScreen
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
