import 'package:flutter/material.dart';
import 'package:villagebanking/theme.dart';

Widget tileSettingsItem(
  BuildContext context, {
  required String title,
  required IconData icon,
  VoidCallback? onTap,
}) {
  final theme = Theme.of(context);
  return ListTile(
    leading: Icon(icon, color: growthAccent),
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: theme.textTheme.titleLarge!.color,
      ),
    ),
    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    onTap:
        onTap ??
        () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tapped on $title setting.'),
              backgroundColor: growthAccent,
            ),
          );
        },
  );
}
