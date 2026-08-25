import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/balance_service.dart';
import '../models/balance.dart';
import 'data_version.dart';
import 'transaction_provider.dart' show syncTickProvider;

final balanceServiceProvider = Provider<BalanceService>((ref) {
  return BalanceService();
});

final balanceProvider = FutureProvider.family<Balance?, ({String peerId, String groupId})>((ref, params) async {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider);
  final service = ref.watch(balanceServiceProvider);
  return service.getBalance(params.peerId, params.groupId);
});

final groupBalancesProvider = FutureProvider.family<List<Balance>, String>((ref, groupId) async {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider);
  final service = ref.watch(balanceServiceProvider);
  return service.getByGroupId(groupId);
});
