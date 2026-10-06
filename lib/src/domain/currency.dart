/// A currency the app can denominate amounts in.
final class CurrencyInfo {
  /// Display symbol, e.g. `'ZK'`, `'KSh'`.
  final String symbol;

  /// Full name, e.g. `'Zambian Kwacha'`.
  final String name;

  /// Digits after the point when formatting.
  final int decimals;

  /// True for the fallback currency (ZMW).
  final bool isDefault;

  /// Creates a currency description.
  const CurrencyInfo({
    required this.symbol,
    required this.name,
    required this.decimals,
    this.isDefault = false,
  });

  /// Formats [amount] as `'<symbol> <fixed>'`.
  String format(double amount) {
    final String fixed = amount.toStringAsFixed(decimals);
    return '$symbol $fixed';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrencyInfo &&
          symbol == other.symbol &&
          name == other.name &&
          decimals == other.decimals &&
          isDefault == other.isDefault;

  @override
  int get hashCode => Object.hash(symbol, name, decimals, isDefault);
}

/// The currencies groups may choose from.
abstract final class CurrencyConfig {
  /// ISO code → description. ZMW is the default.
  static const Map<String, CurrencyInfo> supported = {
    'ZMW': CurrencyInfo(
      symbol: 'ZK',
      name: 'Zambian Kwacha',
      decimals: 2,
      isDefault: true,
    ),
    'KES': CurrencyInfo(
      symbol: 'KSh',
      name: 'Kenyan Shilling',
      decimals: 0,
    ),
    'UGX': CurrencyInfo(
      symbol: 'UGX',
      name: 'Ugandan Shilling',
      decimals: 0,
    ),
    'TZS': CurrencyInfo(
      symbol: 'TSh',
      name: 'Tanzanian Shilling',
      decimals: 0,
    ),
    'USD': CurrencyInfo(symbol: r'$', name: 'US Dollar', decimals: 2),
    'NGN': CurrencyInfo(symbol: '₦', name: 'Nigerian Naira', decimals: 0),
    'ZAR': CurrencyInfo(symbol: 'R', name: 'South African Rand', decimals: 2),
    'GHS': CurrencyInfo(symbol: 'GH₵', name: 'Ghanaian Cedi', decimals: 2),
  };

  /// The fallback currency (ZMW).
  static CurrencyInfo get defaultCurrency => supported['ZMW']!;

  /// The description for [code], or null when unsupported.
  static CurrencyInfo? getInfo(String code) => supported[code];

  /// True when [code] names a supported currency.
  static bool isSupported(String code) => supported.containsKey(code);
}
