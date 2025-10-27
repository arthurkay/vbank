import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/loan.model.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:brick_core/query.dart';
import 'package:villagebanking/screens/loan_repayments.dart';

class LoanTile extends StatefulWidget {
  final Loan loan;

  const LoanTile({super.key, required this.loan});

  @override
  State<LoanTile> createState() => _LoanTileState();
}

class _LoanTileState extends State<LoanTile> {
  Future<Profile?>? _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
  }

  Future<Profile?> _fetchProfile() async {
    final profiles = await Repository().get<Profile>(
      query: Query.where('id', widget.loan.memberId),
    );
    return profiles.isNotEmpty ? profiles.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.monetization_on),
        title: FutureBuilder<Profile?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Loading...');
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              return Text('Member: ${widget.loan.memberId}');
            }
            final profile = snapshot.data!;
            return Text(profile.fullName ?? 'N/A');
          },
        ),
        subtitle: Text(
          'Balance: ${widget.loan.currentBalance}',
        ),
        trailing: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => LoanRepaymentsScreen(loanId: widget.loan.id),
              ),
            );
          },
          child: const Text('View Repayments'),
        ),
      ),
    );
  }
}
