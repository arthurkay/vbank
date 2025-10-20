import 'package:flutter/material.dart';
import 'package:villagebanking/brick/moodels/activity.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:intl/intl.dart';

class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Feed'),
      ),
      body: StreamBuilder<List<Activity>>(
        stream: Repository().subscribe<Activity>(),
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
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.notifications),
                  title: Text(activity.description),
                  subtitle: Text('Type: ${activity.type}'),
                  trailing: Text(DateFormat.yMd().format(activity.createdAt)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
