import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

import '../models/property_model.dart';

/// Mirrors iOS `StripeService` + the booking-request flow in
/// `AirbnbPropertyDetailView.swift`.
///
/// Payment model (identical to iOS — no upfront charge):
///   1. Guest submits a booking REQUEST → `host_bookings` doc, status `pending`,
///      paymentStatus `unpaid` (see [submitBookingRequest]).
///   2. Host accepts → Cloud Function `hostUpdateBookingStatus` → `confirmed`.
///   3. Guest pays from My Stays → [presentConfirmedBookingPaymentSheet]
///      (`createBookingPaymentIntent` → PaymentSheet → `finalizeHostBookingPayment`).
class StripeService {
  StripeService([FirebaseFunctions? functions])
      : _fns = functions ??
            FirebaseFunctions.instanceFor(region: _functionsRegion);

  final FirebaseFunctions _fns;

  /// Must match the region the Cloud Functions are deployed to (same as iOS).
  static const String _functionsRegion = 'us-central1';

  // ── Booking request (STEP 1 — no payment) ──────────────────────────────────

  /// Submits a booking request to `host_bookings` with `status: pending`.
  ///
  /// Field names, fee math, and lifecycle values mirror
  /// iOS `AirbnbPropertyDetailView.submitBooking` exactly:
  ///   platformFee = guestBase * p / (1 - p)   where p = serviceFee% / 100
  ///   total       = guestBase + platformFee
  ///
  /// Returns the new booking document id.
  Future<String> submitBookingRequest({
    required PropertyModel property,
    required String guestId,
    required String guestName,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
  }) async {
    final db = FirebaseFirestore.instance;
    final airbnb = property.airbnbInfo;
    final nightlyRate = airbnb?.nightlyRate ?? property.price;
    final cleaningFee = airbnb?.cleaningFee ?? 0.0;
    final serviceFeePercent = airbnb?.serviceFee ?? 0.0;
    final hostId = property.hostUserId ?? property.realtorId ?? property.ownerId ?? '';

    final nights = checkOut.difference(checkIn).inDays.clamp(1, 365);

    // ── STEP 1: overlap check (mirrors iOS) ──────────────────────────────────
    // Server rules still reject double-bookings; this is a UX pre-check.
    bool hasOverlap = false;
    try {
      final overlapSnap = await db
          .collection('host_bookings')
          .where('propertyId', isEqualTo: property.id)
          .where('status', whereIn: ['pending', 'confirmed'])
          .get();
      for (final doc in overlapSnap.docs) {
        final d = doc.data();
        final existingIn = (d['checkInDate'] as Timestamp?)?.toDate();
        final existingOut = (d['checkOutDate'] as Timestamp?)?.toDate();
        if (existingIn == null || existingOut == null) continue;
        if (checkIn.isBefore(existingOut) && existingIn.isBefore(checkOut)) {
          hasOverlap = true;
          break;
        }
      }
    } catch (_) {
      // Availability query failed (permissions/network) — proceed optimistically,
      // same as iOS: the server create rule still rejects double-bookings.
    }
    if (hasOverlap) {
      throw Exception('Selected dates are no longer available.');
    }

    // ── STEP 2: fee math (identical to iOS) ─────────────────────────────────
    final guestBase = (nightlyRate * nights) + cleaningFee;
    final p = serviceFeePercent / 100.0;
    if (p >= 1) {
      throw Exception('Invalid service fee percentage.');
    }
    final platformFeeAmount = guestBase * (p / (1.0 - p));
    final totalAmount = guestBase + platformFeeAmount;
    final hostNetAmount = guestBase < 0 ? 0.0 : guestBase;

    // ── STEP 3: write the booking request ───────────────────────────────────
    final bookingRef = db.collection('host_bookings').doc();
    await bookingRef.set({
      'id': bookingRef.id,
      'propertyId': property.id,
      'propertyTitle': property.title,
      'propertyImageURL': property.heroImageUrl ?? '',
      'propertyAddress': property.fullAddress,
      'hostId': hostId,
      'guestId': guestId,
      'guestName': guestName,
      'numberOfGuests': guestCount,
      'checkInDate': Timestamp.fromDate(checkIn),
      'checkOutDate': Timestamp.fromDate(checkOut),
      'nightlyRate': nightlyRate,
      'totalNights': nights,
      'totalAmount': totalAmount,

      // Lifecycle
      'status': 'pending',

      // Payment state (backend + webhook are the source of truth)
      'paymentStatus': 'unpaid',
      'escrowReleaseStatus': 'not_released',
      'paymentMethodType': 'stripe_after_approval',
      'currency': 'usd',
      'platformFeeAmount': platformFeeAmount,
      'hostNetAmount': hostNetAmount,
      'serviceFeePercentApplied': serviceFeePercent,
      'launchPromoApplied': false,

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return bookingRef.id;
  }

  // ── Booking payment (STEP 3 — after host confirms) ─────────────────────────

  /// `createBookingPaymentIntent` → PaymentSheet → `finalizeHostBookingPayment`.
  /// Mirrors the full iOS payment sequence including the finalize fallback,
  /// which marks the booking `paid` even if the Stripe webhook is delayed.
  ///
  /// Throws on cancel/failure — handle in the caller.
  Future<void> presentConfirmedBookingPaymentSheet({
    required String bookingId,
  }) async {
    final callable = _fns.httpsCallable('createBookingPaymentIntent');
    final result = await callable.call(<String, dynamic>{
      'bookingId': bookingId,
    });

    final data =
        Map<String, dynamic>.from(result.data as Map<dynamic, dynamic>);
    final clientSecret = data['clientSecret'] as String? ?? '';
    if (clientSecret.isEmpty) {
      throw Exception('Missing clientSecret from createBookingPaymentIntent.');
    }

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'Property Pulse',
        style: ThemeMode.system,
      ),
    );

    await Stripe.instance.presentPaymentSheet();

    // Webhook fallback — iOS `finalizeHostBookingPayment`: sync the booking to
    // `paid` if Stripe shows `succeeded`. Idempotent with webhook processing.
    try {
      await _fns
          .httpsCallable('finalizeHostBookingPayment')
          .call(<String, dynamic>{'bookingId': bookingId});
    } catch (_) {
      // Best-effort: the webhook will still mark the booking paid.
    }
  }

  // ── Stripe Connect (host onboarding + payout status) ───────────────────────

  /// `POST /createStripeAccountLink` — creates/returns a Stripe Express
  /// onboarding URL for host payouts. Mirrors iOS `createStripeAccountLink`.
  Future<Uri> createStripeAccountLink(String userId) async {
    final endpoint = await _httpEndpoint('createStripeAccountLink');
    final body = await _authedPost(endpoint, {'userId': userId});
    final url = body['url'] as String? ?? '';
    if (url.isEmpty) {
      throw Exception('Invalid onboarding URL from createStripeAccountLink.');
    }
    return Uri.parse(url);
  }

  /// `POST /syncStripeConnectStatus` — refreshes `payoutsEnabled` /
  /// `chargesEnabled` in Firestore from Stripe. Mirrors iOS.
  Future<({bool payoutsEnabled, bool chargesEnabled})>
      syncStripeConnectStatus(String userId) async {
    final endpoint = await _httpEndpoint('syncStripeConnectStatus');
    final body = await _authedPost(endpoint, {'userId': userId});
    return (
      payoutsEnabled: body['payoutsEnabled'] as bool? ?? false,
      chargesEnabled: body['chargesEnabled'] as bool? ?? false,
    );
  }

  // ── HTTP helpers (iOS uses raw HTTP + ID token for the Connect endpoints) ──

  Future<Uri> _httpEndpoint(String name) async {
    final projectId = Firebase.app().options.projectId;
    if (projectId.isEmpty) {
      throw Exception('Missing Firebase project id.');
    }
    return Uri.parse(
        'https://$_functionsRegion-$projectId.cloudfunctions.net/$name');
  }

  Future<Map<String, dynamic>> _authedPost(
      Uri endpoint, Map<String, dynamic> payload) async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated.');
    final idToken = await user.getIdToken();

    final resp = await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(payload),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Backend error (${resp.statusCode}): ${resp.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }
}
