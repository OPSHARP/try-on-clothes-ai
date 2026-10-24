import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../constants/app_constants.dart';
import 'storage_service.dart';

/// Simplified billing service for a single monthly subscription
/// that removes all ads ($99.99/month, product ID: `monthly_remove_ads`).
///
/// Uses the [in_app_purchase] plugin to connect with Google Play Billing
/// and Apple App Store (StoreKit).
class SubscriptionService {
  final InAppPurchase _purchase;
  final StorageService _storage;
  final void Function(bool isAdFree)? onAdFreeChanged;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Whether the device supports purchasing (e.g. not running on desktop/web).
  bool _available = false;
  bool get isAvailable => _available;

  /// The subscription product details (once loaded).
  ProductDetails? _productDetails;
  ProductDetails? get productDetails => _productDetails;

  /// Formatted localized price from Google Play, or fallback to $4.99.
  String get displayPrice =>
      _productDetails?.price ??
      '\$${AppConstants.subscriptionPriceUSD.toStringAsFixed(2)}';

  /// Local ad-free flag (also persisted via [StorageService]).
  bool get isAdFree => _storage.isAdFree;

  SubscriptionService({
    required InAppPurchase purchase,
    required StorageService storage,
    this.onAdFreeChanged,
  }) : _purchase = purchase,
       _storage = storage;

  /// Initialize: check platform availability, fetch product details,
  /// and restore any previous purchase.
  Future<void> initialize() async {
    _available = await _purchase.isAvailable();
    if (!_available) return;

    // Listen for purchase updates (including restored purchases).
    _subscription = _purchase.purchaseStream.listen(_onPurchaseUpdate);

    // Fetch the subscription product details across supported product IDs.
    final productResponse = await _purchase.queryProductDetails(
      AppConstants.subscriptionProductIds,
    );
    if (productResponse.error != null) {
      debugPrint(
        'SubscriptionService: error fetching products — '
        '${productResponse.error}',
      );
      return;
    }
    if (productResponse.productDetails.isNotEmpty) {
      _productDetails = productResponse.productDetails.firstWhere(
        (p) => p.id == AppConstants.subscriptionProductId,
        orElse: () => productResponse.productDetails.first,
      );
    }

    // Restore existing purchases.
    await _restorePurchases();
  }

  /// Purchase the monthly subscription.
  Future<bool> purchaseSubscription() async {
    if (!_available || _productDetails == null) return false;

    final PurchaseParam purchaseParam;
    if (defaultTargetPlatform == TargetPlatform.android) {
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: _productDetails!,
        applicationUserName: null,
        changeSubscriptionParam: null,
      );
    } else {
      purchaseParam = PurchaseParam(
        productDetails: _productDetails!,
      );
    }

    // Await the purchase Future to ensure the transaction is actually initiated.
    // The buyNonConsumable returns true if the purchase flow was started successfully.
    final bool purchaseStarted = await _purchase.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
    return purchaseStarted;
  }

  /// Restore purchases (primarily for iOS, but also checks Android).
  Future<void> restorePurchases() => _restorePurchases();

  Future<void> _restorePurchases() async {
    if (!_available) return;

    try {
      // Queries past/active purchases and delivers them via the purchaseStream.
      // Works across both Android (Google Play) and iOS/macOS (StoreKit).
      await _purchase.restorePurchases();
    } catch (e) {
      debugPrint('SubscriptionService: restore error — $e');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      // Grant ad-free status in storage and notify listeners
      await _storage.setIsAdFree(true);
      onAdFreeChanged?.call(true);
      debugPrint(
        'SubscriptionService: ad-free granted for product '
        '${purchase.productID}',
      );
    } else if (purchase.status == PurchaseStatus.canceled ||
        purchase.status == PurchaseStatus.error) {
      debugPrint(
        'SubscriptionService: purchase failed/cancelled '
        '${purchase.productID}',
      );
    }

    // Complete the purchase (required for non-consumables on Android).
    if (purchase.pendingCompletePurchase) {
      await _purchase.completePurchase(purchase);
    }
  }

  /// Dispose the subscription.
  void dispose() {
    _subscription?.cancel();
  }
}
