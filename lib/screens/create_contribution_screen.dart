import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/contribution.model.dart';
import 'package:villagebanking/brick/moodels/group_member.model.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:brick_core/query.dart';

class CreateContributionScreen extends StatefulWidget {
  final String groupId;

  const CreateContributionScreen({super.key, required this.groupId});

  @override
  State<CreateContributionScreen> createState() =>
      _CreateContributionScreenState();
}

class _CreateContributionScreenState extends State<CreateContributionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String? _selectedMemberId;
  final List<Profile> _groupMembers = [];

  @override
  void initState() {
    super.initState();
    _fetchGroupMembers();
  }

  Future<void> _fetchGroupMembers() async {
    final groupMembers = await Repository().get<GroupMember>(
      query: Query.where('groupId', widget.groupId),
    );
    for (var member in groupMembers) {
      final profile = await Repository().get<Profile>(
        query: Query.where('id', member.memberId),
      );
      if (profile.isNotEmpty) {
        setState(() {
          _groupMembers.add(profile.first);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Contribution'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                ),
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
              DropdownButtonFormField<String>(
                value: _selectedMemberId,
                decoration: const InputDecoration(
                  labelText: 'Member',
                  border: OutlineInputBorder(),
                ),
                items: _groupMembers.map((member) {
                  return DropdownMenuItem(
                    value: member.id,
                    child: Text(member.fullName ?? 'Unknown'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedMemberId = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a member';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final contribution = Contribution(
                      amount: double.parse(_amountController.text),
                      memberId: _selectedMemberId!,
                      groupId: widget.groupId,
                      transactionDate: DateTime.now(),
                    );
                    await Repository().upsert<Contribution>(contribution);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
