import '../ui/ui.dart';

class BalanceCard extends StatelessWidget {
  final double balance;
  final String currency;
  final String? label;

  const BalanceCard({super.key, required this.balance, this.currency = 'ZK', this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[Text(label!).small.muted, const Gap(8)],
          Text(
            '$currency ${balance.toStringAsFixed(2)}',
            style: TextStyle(color: balance >= 0 ? scheme.primary : scheme.destructive),
          ).x2Large.bold,
        ],
      ),
    );
  }
}
