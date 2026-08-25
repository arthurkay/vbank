import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped after any *local* write that changes derived data (balances,
/// reports). Inbound changes already arrive through `syncTickProvider`; this is
/// the local counterpart, so a freshly recorded transaction, loan repayment or
/// dissolution updates every derived view immediately.
final dataVersionProvider = StateProvider<int>((ref) => 0);

void bumpDataVersion(Ref ref) => ref.read(dataVersionProvider.notifier).state++;
