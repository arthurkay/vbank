import 'package:brick_core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/brick/moodels/loan.model.dart';
import 'package:villagebanking/brick/moodels/loan_repayment.model.dart';

class CreateLoanRepaymentScreen extends StatefulWidget {
  final String groupId;
  final String memberId;

  const CreateLoanRepaymentScreen({
    super.key,
    required this.groupId,
    required this.memberId,
  });

  @override
  _CreateLoanRepaymentScreenState createState() =>
      _CreateLoanRepaymentScreenState();
}

class _CreateLoanRepaymentScreenState extends State<CreateLoanRepaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  Loan? _selectedLoan;
  List<Loan> _loans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLoans();
  }

  Future<void> _fetchLoans() async {
    final repository = Repository();
    final loans = await repository.get<Loan>(
      query: Query.where(
        'memberId',
        widget.memberId,
      ), //.isExactly(widget.memberId),
    );
    setState(() {
      _loans = loans.toList();
      _isLoading = false;
    });
  }

  Future<void> _saveRepayment() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final newRepayment = LoanRepayment(
        loanId: _selectedLoan!.id,
        amount: double.parse(_amountController.text),
        paymentDate: _selectedDate,
      );

      final repository = Repository();
      await repository.upsert<LoanRepayment>(newRepayment);

      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Loan Repayment')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    DropdownButtonFormField<Loan>(
                      value: _selectedLoan,
                      decoration: const InputDecoration(labelText: 'Loan'),
                      items: _loans.map((loan) {
                        return DropdownMenuItem<Loan>(
                          value: loan,
                          child: Text(
                            'Loan of ${loan.principalAmount} on ${DateFormat.yMd().format(loan.disbursementDate)}',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedLoan = value;
                        });
                      },
                      validator: (value) =>
                          value == null ? 'Please select a loan' : null,
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'Amount'),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter an amount';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Payment Date: ${DateFormat.yMd().format(_selectedDate)}',
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2101),
                            );
                            if (pickedDate != null &&
                                pickedDate != _selectedDate) {
                              setState(() {
                                _selectedDate = pickedDate;
                              });
                            }
                          },
                          child: const Text('Select Date'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _saveRepayment,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
