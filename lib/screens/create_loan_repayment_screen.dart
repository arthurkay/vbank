import 'package:flutter/material.dart';

class CreateLoanRepaymentScreen extends StatelessWidget {
  final String groupId;
  final String memberId;

  const CreateLoanRepaymentScreen({super.key, required this.groupId, required this.memberId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Loan Repayment'),
      ),
      body: Center(
        child: Text('Form to create a new loan repayment for Group ID: $groupId, Member ID: $memberId'),
      ),
    );
  }
}
