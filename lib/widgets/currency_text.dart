import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../core/crypto/currency.dart';

class CurrencyText extends StatelessWidget {
  final double amount;
  final String currency;
  final TextStyle? style;

  const CurrencyText({super.key, required this.amount, this.currency = 'ZMW', this.style});

  @override
  Widget build(BuildContext context) {
    final info = CurrencyConfig.getInfo(currency);
    final symbol = info?.symbol ?? currency;
    final formatted = '$symbol ${amount.toStringAsFixed(info?.decimals ?? 2)}';
    return Text(formatted, style: style);
  }
}
