import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/loan_repayment.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:intl/intl.dart';
import 'package:brick_core/query.dart';

class LoanRepaymentsScreen extends StatelessWidget {
  final String loanId;

  const LoanRepaymentsScreen({super.key, required this.loanId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loan Repayments')),
      body: StreamBuilder<List<LoanRepayment>>(
        stream: Repository().subscribe<LoanRepayment>(
          query: Query.where('loanId', loanId),
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data == null || snapshot.data!.isEmpty) {
            return const Center(child: Text('No repayments found.'));
          }

          final repayments = snapshot.data!;

          return ListView.builder(
            itemCount: repayments.length,
            itemBuilder: (context, index) {
              final repayment = repayments[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.payment),
                  title: Text('Amount: ${repayment.amount}'),
                  trailing: Text(
                    DateFormat.yMd().format(repayment.paymentDate),
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
