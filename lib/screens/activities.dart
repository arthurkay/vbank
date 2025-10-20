import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/activity.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/screens/widgets/activity_tile.dart';
import 'package:brick_core/query.dart';

class ActivitiesScreen extends StatelessWidget {
  final String? groupId;

  const ActivitiesScreen({super.key, this.groupId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community Feed')),
      body: StreamBuilder<List<Activity>>(
        stream: Repository().subscribe<Activity>(
          query: groupId != null ? Query.where('groupId', groupId!) : null,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No activities found.'));
          }

          final activities = snapshot.data!;

          return ListView.builder(
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final activity = activities[index];
              return ActivityTile(activity: activity);
            },
          );
        },
      ),
    );
  }
}
