import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/activity.model.dart';
import 'package:villagebanking/brick/moodels/profile.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:brick_core/query.dart';

class ActivityTile extends StatelessWidget {
  final Activity activity;

  const ActivityTile({super.key, required this.activity});

  Future<Profile?> _getProfile(String memberId) async {
    final profiles = await Repository().get<Profile>(
      query: Query.where('id', memberId, limit1: true),
    );
    return profiles.isNotEmpty ? profiles.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.notifications),
        title: FutureBuilder<Profile?>(
          future: _getProfile(activity.memberId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Loading...');
            }
            if (snapshot.hasError) {
              return const Text('Error');
            }
            if (snapshot.hasData && snapshot.data != null) {
              return Text(snapshot.data!.fullName);
            }
            return const Text('Unknown');
          },
        ),
        subtitle: Text(activity.description),
        trailing: Text(activity.type),
      ),
    );
  }
}
