import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const _entitlementId = 'pro';
  static const _apiKey = 'test_AUJLrwtouFihELtHcUQnpnXzxNw';

  final isPro = ValueNotifier<bool>(false);

  Future<void> init() async {
    try {
      Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.error);
      await Purchases.configure(PurchasesConfiguration(_apiKey));
    } catch (e) {
      debugPrint('SubscriptionService init error: $e');
    }
  }

  Future<void> identify(String userId) async {
    try {
      await Purchases.logIn(userId);
      await _refresh();
    } catch (e) {
      debugPrint('SubscriptionService identify error: $e');
    }
  }

  Future<void> _refresh() async {
    try {
      final info = await Purchases.getCustomerInfo();
      isPro.value = info.entitlements.active.containsKey(_entitlementId);
    } catch (e) {
      debugPrint('SubscriptionService refresh error: $e');
    }
  }

  Future<bool> purchase(Package package) async {
    try {
      final info = await Purchases.purchasePackage(package);
      isPro.value = info.entitlements.active.containsKey(_entitlementId);
      return isPro.value;
    } catch (e) {
      debugPrint('SubscriptionService purchase error: $e');
      return false;
    }
  }

  Future<bool> restore() async {
    try {
      final info = await Purchases.restorePurchases();
      isPro.value = info.entitlements.active.containsKey(_entitlementId);
      return isPro.value;
    } catch (e) {
      debugPrint('SubscriptionService restore error: $e');
      return false;
    }
  }
}
