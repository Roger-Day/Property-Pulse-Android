import 'package:cloud_firestore/cloud_firestore.dart';

/// Review categories — mirrors iOS `ReviewCategory` for the 5 categories
/// both platforms' UI actually collects (overall/location/value/
/// cleanliness/communication). iOS additionally has condition/amenities/
/// neighborhood/accessibility/safety with no Flutter rating UI for them
/// (a real but larger deferred gap — adding them means adding rating rows
/// to the write-a-review form, not just this model); Flutter's `accuracy`
/// has no iOS counterpart. [label] is also the exact Firestore rawValue
/// string iOS reads/writes — using `.name` (lowercase) here previously
/// made every rating silently invisible cross-platform.
enum ReviewCategory {
  overall,
  location,
  value,
  cleanliness,
  accuracy,
  communication;

  String get label {
    switch (this) {
      case ReviewCategory.overall:
        return 'Overall';
      case ReviewCategory.location:
        return 'Location';
      case ReviewCategory.value:
        return 'Value';
      case ReviewCategory.cleanliness:
        return 'Cleanliness';
      case ReviewCategory.accuracy:
        return 'Accuracy';
      case ReviewCategory.communication:
        return 'Communication';
    }
  }
}

/// Review types — mirrors iOS `ReviewType` exactly (general/stay/visit/
/// purchase/rental describe the kind of interaction the review follows).
/// Previously this enum had unrelated buyer/renter/investor cases invented
/// independently of iOS, so a `reviewType` written by either platform was
/// silently unrecognized by the other (both default to `.general` on an
/// unmatched value, so no crash — just a lost category, which is exactly
/// the "silently invisible" class of bug already found in `categoryRatings`
/// below).
enum ReviewType {
  general,
  stay,
  visit,
  purchase,
  rental;

  /// Also iOS's exact Firestore rawValue string for this case — see
  /// [ReviewModel.toFirestore].
  String get label {
    switch (this) {
      case ReviewType.general:
        return 'General';
      case ReviewType.stay:
        return 'Stay';
      case ReviewType.visit:
        return 'Visit';
      case ReviewType.purchase:
        return 'Purchase';
      case ReviewType.rental:
        return 'Rental';
    }
  }
}

class ReviewModel {
  const ReviewModel({
    required this.id,
    required this.propertyId,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.rating,
    required this.title,
    required this.comment,
    required this.date,
    this.helpfulCount = 0,
    this.isVerified = false,
    this.reviewType = ReviewType.general,
    this.categoryRatings = const {},
  });

  final String id;
  final String propertyId;
  final String userId;
  final String userName;
  final String? userImage;
  final int rating;
  final String title;
  final String comment;
  final DateTime date;
  final int helpfulCount;
  final bool isVerified;
  final ReviewType reviewType;
  final Map<ReviewCategory, int> categoryRatings;

  factory ReviewModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ReviewModel._fromMap(doc.id, data);
  }

  factory ReviewModel.fromQueryDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return ReviewModel._fromMap(doc.id, doc.data());
  }

  factory ReviewModel._fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return DateTime.now();
    }

    ReviewType parseType(dynamic value) {
      // Case-insensitive so both iOS's capitalized rawValues ("Stay") and
      // Flutter's own enum-name writes ("stay") parse correctly.
      final v = (value as String? ?? '').toLowerCase();
      for (final t in ReviewType.values) {
        if (t.name == v) return t;
      }
      return ReviewType.general;
    }

    Map<ReviewCategory, int> parseCategoryRatings(dynamic value) {
      if (value is! Map) return {};
      final out = <ReviewCategory, int>{};
      for (final entry in value.entries) {
        final key = (entry.key as String? ?? '').toLowerCase();
        final val = (entry.value as num?)?.toInt() ?? 0;
        for (final cat in ReviewCategory.values) {
          // Matches both iOS's capitalized rawValue ("Cleanliness") and
          // Flutter's pre-fix lowercase writes ("cleanliness").
          if (cat.name == key) {
            out[cat] = val;
            break;
          }
        }
      }
      return out;
    }

    return ReviewModel(
      id: id,
      propertyId: data['propertyId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      userName: data['userName'] as String? ?? 'Reviewer',
      userImage: data['userImage'] as String?,
      rating: (data['rating'] as num?)?.toInt() ?? 5,
      title: data['title'] as String? ?? '',
      comment: data['comment'] as String? ?? '',
      date: parseDate(data['date'] ?? data['createdAt']),
      helpfulCount: (data['helpfulCount'] as num?)?.toInt() ?? 0,
      isVerified: data['isVerified'] as bool? ?? false,
      reviewType: parseType(data['reviewType']),
      categoryRatings: parseCategoryRatings(data['categoryRatings']),
    );
  }

  Map<String, dynamic> toFirestore() {
    // Write iOS's exact capitalized rawValue strings (`label`, not `.name`)
    // so a review written on Android is actually readable on iOS — see the
    // doc comments on ReviewType/ReviewCategory above.
    final catMap = <String, int>{};
    for (final entry in categoryRatings.entries) {
      catMap[entry.key.label] = entry.value;
    }
    return {
      'propertyId': propertyId,
      'userId': userId,
      'userName': userName,
      if (userImage != null) 'userImage': userImage,
      'rating': rating,
      'title': title,
      'comment': comment,
      'date': Timestamp.fromDate(date),
      'helpfulCount': helpfulCount,
      'isVerified': isVerified,
      'reviewType': reviewType.label,
      'categoryRatings': catMap,
    };
  }
}

/// Computed statistics from a list of reviews.
class ReviewStats {
  const ReviewStats({
    required this.averageRating,
    required this.totalReviews,
    required this.ratingDistribution,
    required this.verifiedCount,
  });

  final double averageRating;
  final int totalReviews;
  final Map<int, int> ratingDistribution; // star (1-5) → count
  final int verifiedCount;

  factory ReviewStats.fromReviews(List<ReviewModel> reviews) {
    if (reviews.isEmpty) {
      return const ReviewStats(
        averageRating: 0,
        totalReviews: 0,
        ratingDistribution: {},
        verifiedCount: 0,
      );
    }
    final dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    var sum = 0;
    var verified = 0;
    for (final r in reviews) {
      final star = r.rating.clamp(1, 5);
      dist[star] = (dist[star] ?? 0) + 1;
      sum += r.rating;
      if (r.isVerified) verified++;
    }
    return ReviewStats(
      averageRating: sum / reviews.length,
      totalReviews: reviews.length,
      ratingDistribution: dist,
      verifiedCount: verified,
    );
  }
}
