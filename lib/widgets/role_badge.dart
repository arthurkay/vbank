import 'package:shadcn_flutter/shadcn_flutter.dart';

class RoleBadge extends StatelessWidget {
  final String role;
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) => switch (role) {
        'owner' => const PrimaryBadge(child: Text('Owner')),
        'admin' => const SecondaryBadge(child: Text('Admin')),
        _ => const OutlineBadge(child: Text('Member')),
      };
}
