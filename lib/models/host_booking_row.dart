import 'package:cloud_firestore/cloud_firestore.dart';

/// Which Firestore collection a guest booking row belongs to — affects cancel,
/// listeners, and Pay Now (callable targets `host_bookings` ids on iOS).
enum GuestBookingFirestoreCollection {
  bookings('bookings'),
  hostBookings('host_bookings');

  const GuestBookingFirestoreCollection(this.collectionId);
  final String collectionId;
}

/// Display model for booking documents from both the `bookings` collection
/// (written by [StripeService]) and the legacy `host_bookings` collection.
///
/// Field aliases cover both naming conventions so a single `fromDoc` call works
/// for Stripe-created documents (`checkIn`, `guestCount`, `currencyCode`) and
/// legacy documents (`checkInDate`, `numberOfGuests`, `currency`).
class HostBookingRow {
  HostBookingRow({
    required this.id,
    required this.propertyId,
    required this.firestoreCollection,
    this.hostId,
    this.guestId,
    this.guestName,
    this.propertyTitle,
    this.propertyImageUrl,
    this.propertyAddress,
    this.checkIn,
    this.checkOut,
    this.statusLabel,
    this.totalAmount,
    this.currencyCode,
    this.numberOfGuests,
    this.paymentStatus,
    this.cancellationPolicyId,
  });

  final String id;
  final String propertyId;
  /// Where this row's document lives (`bookings` vs `host_bookings`).
  final GuestBookingFirestoreCollection firestoreCollection;

  /// Host user id for messaging / routing (may be empty on legacy docs).
  final String? hostId;

  /// Guest user id — needed to start a conversation from the host's
  /// dashboard ("Message Guest"). Mirrors iOS `HostBooking.guestId`.
  final String? guestId;

  /// Denormalized at booking-creation time, same as iOS's `HostBooking.guestName`
  /// (read straight off the booking doc, never a live join).
  final String? guestName;

  final String? propertyTitle;
  final String? propertyImageUrl;
  final String? propertyAddress;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String? statusLabel;
  final double? totalAmount;
  final String? currencyCode;
  final int? numberOfGuests;
  final String? paymentStatus;

  /// Present on the newer escrow-system bookings (`bookings` collection);
  /// null on legacy `host_bookings` docs, which predate the tiered
  /// cancellation-policy system. Used for the pre-cancellation refund
  /// preview — `CancellationService.fetchPolicy` falls back to `flexible`
  /// when this is null.
  final String? cancellationPolicyId;

  factory HostBookingRow.fromDoc(
    String id,
    Map<String, dynamic> data, {
    GuestBookingFirestoreCollection? firestoreCollection,
  }) {
    final fc = firestoreCollection ?? _inferFirestoreCollection(data);

    final propertyId = data['propertyId'] as String? ??
        data['property_id'] as String? ??
        data['listingId'] as String? ??
        '';

    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    // Stripe writes 'checkIn' / 'checkOut'; legacy docs use 'checkInDate' etc.
    final checkIn = ts(data['checkIn']) ??
        ts(data['checkInDate']) ??
        ts(data['check_in_date']) ??
        ts(data['startDate']);
    final checkOut = ts(data['checkOut']) ??
        ts(data['checkOutDate']) ??
        ts(data['check_out_date']) ??
        ts(data['endDate']);

    final statusRaw =
        (data['status'] as String? ?? 'pending').toLowerCase();
    String statusLabel;
    switch (statusRaw) {
      case 'confirmed':
      case 'accepted':
        statusLabel = 'Confirmed';
        break;
      case 'cancelled':
      case 'canceled':
        statusLabel = 'Cancelled';
        break;
      case 'declined':
      case 'rejected':
        statusLabel = 'Declined';
        break;
      case 'completed':
        statusLabel = 'Completed';
        break;
      default:
        statusLabel = 'Pending';
    }

    final total = (data['totalAmount'] as num?)?.toDouble() ??
        (data['total_amount'] as num?)?.toDouble();
    // Stripe writes 'currencyCode'; legacy writes 'currency'.
    final currency = ((data['currencyCode'] as String?) ??
            (data['currency'] as String?) ??
            'USD')
        .toUpperCase();
    // Stripe writes 'guestCount'; legacy writes 'numberOfGuests'.
    final guests = (data['guestCount'] as num?)?.toInt() ??
        (data['numberOfGuests'] as num?)?.toInt() ??
        (data['number_of_guests'] as num?)?.toInt();

    final payment = ((data['paymentStatus'] as String?) ??
            (data['payment_status'] as String?))
        ?.toLowerCase();

    final cancellationPolicyId = data['cancellationPolicyId'] as String?;

    final hostRaw = data['hostId'] as String? ??
        data['host_id'] as String? ??
        data['hostUserId'] as String? ??
        data['host_user_id'] as String?;

    final guestIdRaw = data['guestId'] as String? ??
        data['guest_id'] as String? ??
        data['userId'] as String? ??
        data['user_id'] as String?;
    final guestNameRaw = data['guestName'] as String? ??
        data['guest_name'] as String? ??
        data['userName'] as String? ??
        data['user_name'] as String?;

    return HostBookingRow(
      id: id,
      propertyId: propertyId,
      firestoreCollection: fc,
      hostId: hostRaw?.trim().isEmpty == true ? null : hostRaw?.trim(),
      guestId: guestIdRaw?.trim().isEmpty == true ? null : guestIdRaw?.trim(),
      guestName: guestNameRaw?.trim().isEmpty == true ? null : guestNameRaw?.trim(),
      propertyTitle: data['propertyTitle'] as String? ??
          data['property_title'] as String?,
      propertyImageUrl: data['propertyImageURL'] as String? ??
          data['property_image_url'] as String?,
      propertyAddress: data['propertyAddress'] as String? ??
          data['property_address'] as String? ??
          data['location'] as String?,
      checkIn: checkIn,
      checkOut: checkOut,
      statusLabel: statusLabel,
      totalAmount: total,
      currencyCode: currency,
      numberOfGuests: guests,
      paymentStatus: payment,
      cancellationPolicyId: cancellationPolicyId?.trim().isEmpty == true
          ? null
          : cancellationPolicyId?.trim(),
    );
  }

  static GuestBookingFirestoreCollection _inferFirestoreCollection(
    Map<String, dynamic> data,
  ) {
    final s = data['_sourceCollection'] as String?;
    if (s == GuestBookingFirestoreCollection.bookings.collectionId) {
      return GuestBookingFirestoreCollection.bookings;
    }
    return GuestBookingFirestoreCollection.hostBookings;
  }

  String get headline =>
      (propertyTitle?.trim().isNotEmpty == true) ? propertyTitle!.trim() : 'Stay';

  bool get hasDates => checkIn != null && checkOut != null;

  /// Nights between check-in and check-out (minimum 1 when dates exist).
  int get numberOfNights {
    if (!hasDates) return 0;
    final d = checkOut!.difference(checkIn!).inDays;
    return d < 1 ? 1 : d;
  }

  /// Guest may cancel — mirrors iOS `canCancelReservation`.
  bool get canGuestCancelReservation {
    final s = statusLabel?.toLowerCase();
    return s == 'pending' || s == 'confirmed';
  }

  bool get isConfirmedStay => statusLabel?.toLowerCase() == 'confirmed';
}
