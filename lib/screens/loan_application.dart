import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:villagebanking/brick/moodels/activity.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/main.dart';

class LoanApplicationScreen extends StatefulWidget {
  const LoanApplicationScreen({super.key});

  @override
  State<LoanApplicationScreen> createState() => _LoanApplicationScreenState();
}

class _LoanApplicationScreenState extends State<LoanApplicationScreen> {
  final _amountController = TextEditingController();
  final _tenureController = TextEditingController();
  double _interest = 0.0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_calculateInterest);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  void _calculateInterest() {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    setState(() {
      _interest = amount * 0.20;
    });
  }

  void _submitApplication() async {
    final prefs = await SharedPreferences.getInstance();
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final tenure = int.tryParse(_tenureController.text) ?? 0;
    final groupId = prefs.getString('selectedGroupId');

    if (groupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loan application failed, select a group!'),
        ),
      );
      return;
    }

    if (amount > 0 && tenure > 0) {
      final activity = Activity(
        groupId: groupId,
        memberId: supabase.client.auth.currentUser?.id,
        type: 'loan_application',
        description:
            'Loan Amount: $amount, Payment Tenure: $tenure months, Interest Rate: 20%',
      );
      Repository().upsert<Activity>(activity);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loan application submitted!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loan Application')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Loan Amount',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tenureController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Payment Tenure (in months)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Interest (20%): ${_interest.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _submitApplication,
              child: const Text('Submit Application'),
            ),
          ],
        ),
      ),
    );
  }
}
