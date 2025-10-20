import 'package:flutter/material.dart';

class AddUserToGroupScreen extends StatelessWidget {
  final String groupId;

  const AddUserToGroupScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add User to Group'),
      ),
      body: Center(
        child: Text('Add User to Group Screen for Group ID: $groupId'),
      ),
    );
  }
}
