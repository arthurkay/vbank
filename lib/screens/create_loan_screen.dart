import 'package:flutter/material.dart';

class CreateLoanScreen extends StatefulWidget {
  final String groupId;
  final String memberId;

  const CreateLoanScreen({super.key, required this.groupId, required this.memberId});

  @override
  State<CreateLoanScreen> createState() => _CreateLoanScreenState();
}

class _CreateLoanScreenState extends State<CreateLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _interestRateController = TextEditingController();
  final TextEditingController _tenureController = TextEditingController();

  double _monthlyPayment = 0.0;

  @override
  void dispose() {
    _amountController.dispose();
    _interestRateController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  void _calculateMonthlyPayment() {
    if (_formKey.currentState!.validate()) {
      final double amount = double.parse(_amountController.text);
      final double annualInterestRate = double.parse(_interestRateController.text) / 100;
      final int tenureMonths = int.parse(_tenureController.text);

      if (tenureMonths == 0) {
        setState(() {
          _monthlyPayment = amount; // If tenure is 0, pay full amount
        });
        return;
      }

      final double monthlyInterestRate = annualInterestRate / 12;

      if (monthlyInterestRate == 0) {
        setState(() {
          _monthlyPayment = amount / tenureMonths;
        });
      } else {
        // For simplicity, let's assume simple interest for now, or a basic division.
        // A more accurate formula for amortized loan payment (P = L[i(1 + i)^n] / [(1 + i)^n – 1]) is complex.
        // For a simple approximation, we'll just divide principal + total interest by tenure.
        final double totalInterest = amount * annualInterestRate * (tenureMonths / 12);
        setState(() {
          _monthlyPayment = (amount + totalInterest) / tenureMonths;
        });
      }
    }
  }

  void _submitLoan() {
    if (_formKey.currentState!.validate()) {
      // Here you would typically send the loan data to your backend or repository
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submitting loan for ${widget.memberId} in group ${widget.groupId}')),
      );
      // For now, just pop the screen
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Loan'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Loan Amount',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid positive amount';
                  }
                  return null;
                },
                onChanged: (_) => _calculateMonthlyPayment(),
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _interestRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Annual Interest Rate (e.g., 5 for 5%)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an interest rate';
                  }
                  if (double.tryParse(value) == null || double.parse(value) < 0) {
                    return 'Please enter a valid non-negative interest rate';
                  }
                  return null;
                },
                onChanged: (_) => _calculateMonthlyPayment(),
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _tenureController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tenure (Months)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter tenure in months';
                  }
                  if (int.tryParse(value) == null || int.parse(value) <= 0) {
                    return 'Please enter a valid positive number of months';
                  }
                  return null;
                },
                onChanged: (_) => _calculateMonthlyPayment(),
              ),
              const SizedBox(height: 24.0),
              Text(
                'Monthly Payment Summary:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8.0),
              Text(
                _monthlyPayment > 0
                    ? 'Estimated Monthly Payment: \$${_monthlyPayment.toStringAsFixed(2)}'
                    : 'Enter loan details to calculate monthly payment',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: _submitLoan,
                child: const Text('Submit Loan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}