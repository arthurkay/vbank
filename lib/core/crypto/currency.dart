class CurrencyInfo {
  final String symbol;
  final String name;
  final int decimals;
  final bool isDefault;

  const CurrencyInfo({
    required this.symbol,
    required this.name,
    required this.decimals,
    this.isDefault = false,
  });

  String format(double amount) {
    final fixed = amount.toStringAsFixed(decimals);
    return '$symbol $fixed';
  }
}

class CurrencyConfig {
  static const Map<String, CurrencyInfo> supported = {
    'ZMW': CurrencyInfo(
      symbol: 'ZK',
      name: 'Zambian Kwacha',
      decimals: 2,
      isDefault: true,
    ),
    'KES': CurrencyInfo(symbol: 'KSh', name: 'Kenyan Shilling', decimals: 0),
    'UGX': CurrencyInfo(symbol: 'UGX', name: 'Ugandan Shilling', decimals: 0),
    'TZS': CurrencyInfo(symbol: 'TSh', name: 'Tanzanian Shilling', decimals: 0),
    'USD': CurrencyInfo(symbol: r'$', name: 'US Dollar', decimals: 2),
    'NGN': CurrencyInfo(symbol: '₦', name: 'Nigerian Naira', decimals: 0),
    'ZAR': CurrencyInfo(symbol: 'R', name: 'South African Rand', decimals: 2),
    'GHS': CurrencyInfo(symbol: 'GH₵', name: 'Ghanaian Cedi', decimals: 2),
  };

  static CurrencyInfo get defaultCurrency => supported['ZMW']!;

  static CurrencyInfo? getInfo(String code) => supported[code];
}
