import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../repositories/property_repository.dart';
import 'premium_boost_service.dart';

/// Google Play Billing for Premium + listing boosts using the **same product IDs**
/// as iOS `SubscriptionService` / `PremiumBoostService` (StoreKit). Host stay
/// payments use Stripe via Cloud Functions — not this service.
class InAppBillingService extends ChangeNotifier {
  InAppBillingService(this._propertyRepository);

  final PropertyRepository _propertyRepository;

  static const monthlyProductId = 'com.propertypulse.premium.monthly';
  static const yearlyProductId = 'com.propertypulse.premium.yearly';

  // Role-tier subscriptions — same IDs as iOS SubscriptionService.
  static const hostListingsMonthlyId =
      'com.propertypulse.host.listings.monthly';
  static const developerProMonthlyId =
      'com.propertypulse.developer.pro.monthly';
  static const developerGrowthMonthlyId =
      'com.propertypulse.developer.growth.monthly';
  static const ownerProMonthlyId = 'com.propertypulse.owner.pro.monthly';
  static const ownerInvestorMonthlyId =
      'com.propertypulse.owner.investor.monthly';
  static const airbnbHostProMonthlyId =
      'com.propertypulse.airbnbhost.pro.monthly';
  static const airbnbHostPlusMonthlyId =
      'com.propertypulse.airbnbhost.plus.monthly';
  static const realtorProMonthlyId = 'com.propertypulse.realtor.pro.monthly';
  static const realtorEliteMonthlyId =
      'com.propertypulse.realtor.elite.monthly';

  static const boost7Id = 'com.propertypulse.boost.7days';
  static const boost14Id = 'com.propertypulse.boost.14days';
  static const boost30Id = 'com.propertypulse.boost.30days';

  // Boost credit packs — same IDs as iOS PremiumBoostService.
  static const boostPack3Id = 'com.propertypulse.boost.3pack';
  static const boostPack5Id = 'com.propertypulse.boost.5pack';

  static const Set<String> subscriptionProductIds = {
    monthlyProductId,
    yearlyProductId,
    hostListingsMonthlyId,
    developerProMonthlyId,
    developerGrowthMonthlyId,
    ownerProMonthlyId,
    ownerInvestorMonthlyId,
    airbnbHostProMonthlyId,
    airbnbHostPlusMonthlyId,
    realtorProMonthlyId,
    realtorEliteMonthlyId,
  };

  static const Set<String> boostProductIds = {
    boost7Id,
    boost14Id,
    boost30Id,
    boostPack3Id,
    boostPack5Id,
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool storeAvailable = false;
  bool isLoading = true;
  bool isPremium = false;
  String? lastError;

  /// Set when a purchase enters [PurchaseStatus.pending] (e.g. Google Family
  /// Library "Ask to Buy") — distinct from [lastError] since this isn't a
  /// failure, and distinct from the brief in-flight spinner since approval
  /// can take hours or days. Mirrors iOS `SubscriptionError.purchasePending`.
  String? pendingApprovalMessage;

  /// Set while a subscription purchase is in flight (UI parity with iOS plan-row spinner).
  String? purchasingSubscriptionProductId;

  /// Product ID of the currently-active subscription, if any.
  /// Mirrors iOS `SubscriptionStatus.displayName` — lets the UI distinguish
  /// "Premium (Monthly)" from "Premium (Yearly)" once entitlement is confirmed.
  String? activeSubscriptionProductId;

  /// Resolves which tier a legacy purchase should now count as — mirrors
  /// iOS's grandfathering rules: subscribers who bought the old $4.99
  /// host-listings add-on keep Host Pro access, and realtors who bought the
  /// old general Premium plan (before role-tier plans existed) keep Realtor
  /// Pro access. [role] is the signed-in user's role (e.g. 'realtor');
  /// pass null/anything else to skip the realtor-specific rule.
  String? effectiveTierProductId({String? role}) {
    final active = activeSubscriptionProductId;
    if (active == null) return null;
    if (active == hostListingsMonthlyId) return airbnbHostProMonthlyId;
    if ((active == monthlyProductId || active == yearlyProductId) &&
        role == 'realtor') {
      return realtorProMonthlyId;
    }
    return active;
  }

  /// Human-readable plan name — matches iOS `SubscriptionStatus.displayName`.
  String get subscriptionDisplayName {
    switch (activeSubscriptionProductId) {
      case monthlyProductId:
        return 'Premium (Monthly)';
      case yearlyProductId:
        return 'Premium (Yearly)';
      case hostListingsMonthlyId:
        return 'Host Listings';
      case developerProMonthlyId:
        return 'Developer Pro';
      case developerGrowthMonthlyId:
        return 'Developer Growth';
      case ownerProMonthlyId:
        return 'Owner Pro';
      case ownerInvestorMonthlyId:
        return 'Owner Investor';
      case airbnbHostProMonthlyId:
        return 'Host Pro';
      case airbnbHostPlusMonthlyId:
        return 'Host Plus';
      case realtorProMonthlyId:
        return 'Realtor Pro';
      case realtorEliteMonthlyId:
        return 'Realtor Elite';
      default:
        return 'Premium';
    }
  }

  ProductDetails? monthlyProduct;
  ProductDetails? yearlyProduct;
  ProductDetails? boost7Product;
  ProductDetails? boost14Product;
  ProductDetails? boost30Product;

  /// All fetched products keyed by id — role-tier subscriptions and boost
  /// packs are looked up here (the named fields above cover the legacy UI).
  final Map<String, ProductDetails> products = {};

  ProductDetails? productById(String id) => products[id];

  String? _pendingBoostPropertyId;

  /// Increments after a boost purchase is confirmed and Firestore is updated (for UI refresh).
  int boostSuccessGeneration = 0;

  /// Current boost-credit balance — call [refreshBoostCredits] after login
  /// or a pack purchase to keep this current.
  int boostCredits = 0;

  Future<void> refreshBoostCredits() async {
    boostCredits = await PremiumBoostService.loadBoostCredits();
    notifyListeners();
  }

  Future<void> init() async {
    if (kIsWeb) {
      isLoading = false;
      lastError = 'In-app purchases are not available on web.';
      notifyListeners();
      return;
    }

    storeAvailable = await _iap.isAvailable();
    if (!storeAvailable) {
      isLoading = false;
      lastError = 'Store not available.';
      notifyListeners();
      return;
    }

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        lastError = e.toString();
        notifyListeners();
      },
    );

    await _queryProducts();
    unawaited(refreshBoostCredits());

    // Silently rehydrate existing subscribers on launch — mirrors iOS
    // `Transaction.currentEntitlements` check in `SubscriptionService.init()`.
    // The purchase stream delivers any active subscription as a restored
    // purchase, which sets isPremium = true via _onPurchaseUpdates.
    try {
      await _iap.restorePurchases();
    } catch (_) {
      // Swallow — the user can tap "Restore Purchases" manually if this fails.
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> _queryProducts() async {
    final ids = <String>{
      ...subscriptionProductIds,
      ...boostProductIds,
    };
    final response = await _iap.queryProductDetails(ids);
    if (response.error != null) {
      lastError = response.error!.message;
    }
    for (final p in response.productDetails) {
      products[p.id] = p;
      switch (p.id) {
        case monthlyProductId:
          monthlyProduct = p;
          break;
        case yearlyProductId:
          yearlyProduct = p;
          break;
        case boost7Id:
          boost7Product = p;
          break;
        case boost14Id:
          boost14Product = p;
          break;
        case boost30Id:
          boost30Product = p;
          break;
      }
    }
  }

  /// Boost credits granted per pack — mirrors iOS `PremiumBoostService`
  /// pack3 / pack5 consumables. Single-duration boosts return 0.
  int creditsForBoostProduct(String productId) {
    switch (productId) {
      case boostPack3Id:
        return 3;
      case boostPack5Id:
        return 5;
      default:
        return 0;
    }
  }

  Future<void> refreshProducts() async {
    await _queryProducts();
    notifyListeners();
  }

  /// Same role as iOS `SubscriptionService.restorePurchases()` / App Store sync.
  Future<void> restorePurchases() async {
    lastError = null;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> purchasePremium(ProductDetails product) async {
    lastError = null;
    purchasingSubscriptionProductId = product.id;
    notifyListeners();
    final param = PurchaseParam(productDetails: product);
    try {
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      purchasingSubscriptionProductId = null;
      lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Consumable boost: completes with [PremiumBoostService] after Play confirms purchase.
  Future<void> purchaseBoost({
    required ProductDetails product,
    required String propertyId,
  }) async {
    lastError = null;
    _pendingBoostPropertyId = propertyId;
    final param = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: param);
  }

  /// Consumable boost-credit pack purchase — not tied to a property; credits
  /// land in the user's `boostCredits` balance for later redemption via
  /// [redeemBoostCredit].
  Future<void> purchaseBoostPackage(ProductDetails product) async {
    lastError = null;
    final param = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: param);
  }

  /// Spends one boost credit on [propertyId] for [days] — no store purchase
  /// involved, the credit was already paid for via a pack.
  Future<void> redeemBoostCredit({
    required String propertyId,
    required int days,
  }) async {
    lastError = null;
    await PremiumBoostService.applyBoostCredit(
      repository: _propertyRepository,
      propertyId: propertyId,
      days: days,
    );
    await refreshBoostCredits();
    boostSuccessGeneration++;
    notifyListeners();
  }

  int daysForBoostProduct(String productId) {
    switch (productId) {
      case boost7Id:
        return 7;
      case boost14Id:
        return 14;
      case boost30Id:
        return 30;
      default:
        return 7;
    }
  }

  ProductDetails? productForBoostDays(int days) {
    switch (days) {
      case 7:
        return boost7Product;
      case 14:
        return boost14Product;
      case 30:
        return boost30Product;
      default:
        return null;
    }
  }

  /// Writes `plan: "pro"` to `users/{uid}` — mirrors iOS
  /// `SubscriptionService.syncBackendPlan(isActive: true)`. Without this,
  /// the purchase only ever flips the in-memory [isPremium] flag: the
  /// listing-limit Cloud Function (`listing-limit-functions.js`'s
  /// `inferPlan`) and [ListingEntitlements.allowedActiveListingLimit] both
  /// read `users.plan` from Firestore, so a subscriber's listing cap would
  /// silently never actually increase, and the entitlement would vanish on
  /// reinstall since nothing server-visible was ever set.
  ///
  /// For [productId] a Developer Pro/Growth product, also writes
  /// `developerSubscriptionTier` ("pro"/"growth") — the separate field
  /// `developer-monetization-functions.js`'s `onDeveloperProjectCreated`
  /// trigger reads to enforce the 5/20 project cap. Without this, a paying
  /// developer stayed capped at the free tier's 1-project limit server-side
  /// and had every subsequent (already-paid-for) project silently rejected.
  Future<void> _syncBackendPlan(String productId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final patch = <String, Object>{'plan': 'pro'};
      if (productId == developerProMonthlyId) {
        patch['developerSubscriptionTier'] = 'pro';
      } else if (productId == developerGrowthMonthlyId) {
        patch['developerSubscriptionTier'] = 'growth';
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        patch,
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best-effort — same as iOS, which logs and continues rather than
      // failing the purchase over a sync error.
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final pid = purchase.productID;

      if (purchase.status == PurchaseStatus.pending) {
        if (subscriptionProductIds.contains(pid)) {
          purchasingSubscriptionProductId = pid;
        }
        // Most `pending` events resolve within seconds (normal Play Billing
        // processing latency), but the same status also covers genuinely
        // long waits — e.g. Google Family Library "Ask to Buy" needing a
        // family organizer's approval. Surface this so the user isn't left
        // staring at an indefinite spinner with no explanation.
        pendingApprovalMessage = subscriptionProductIds.contains(pid) ||
                boostProductIds.contains(pid)
            ? 'Waiting for purchase approval. If this was made under Family '
                "Library sharing, it may need approval from your family "
                "organizer — we'll update automatically once it's confirmed."
            : pendingApprovalMessage;
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        if (subscriptionProductIds.contains(pid)) {
          purchasingSubscriptionProductId = null;
        }
        lastError = purchase.error?.message ?? 'Purchase failed';
        pendingApprovalMessage = null;
        _pendingBoostPropertyId = null;
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        if (subscriptionProductIds.contains(pid)) {
          purchasingSubscriptionProductId = null;
        }
        pendingApprovalMessage = null;
        _pendingBoostPropertyId = null;
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final id = purchase.productID;
        pendingApprovalMessage = null;

        if (subscriptionProductIds.contains(id)) {
          purchasingSubscriptionProductId = null;
          isPremium = true;
          activeSubscriptionProductId = id;
          await _syncBackendPlan(id);
          await _iap.completePurchase(purchase);
        } else if (boostProductIds.contains(id)) {
          final packCredits = PremiumBoostService.creditsForPackProduct(id);
          if (packCredits > 0) {
            // Boost-credit pack — not tied to a property, credits go to
            // the user's balance for later redemption.
            try {
              await PremiumBoostService.creditBoostPackPurchase(
                transactionId: purchase.purchaseID ?? id,
                credits: packCredits,
              );
              await refreshBoostCredits();
              boostSuccessGeneration++;
            } catch (e) {
              lastError = e.toString();
            }
          } else {
            final propertyId = _pendingBoostPropertyId;
            _pendingBoostPropertyId = null;
            if (propertyId != null) {
              try {
                final days = daysForBoostProduct(id);
                await PremiumBoostService.activateBoost(
                  repository: _propertyRepository,
                  propertyId: propertyId,
                  productId: id,
                  days: days,
                  transactionId: purchase.purchaseID ?? id,
                );
                boostSuccessGeneration++;
              } catch (e) {
                lastError = e.toString();
              }
            }
          }
          await _iap.completePurchase(purchase);
        } else {
          await _iap.completePurchase(purchase);
        }
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
