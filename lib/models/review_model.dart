import 'package:cloud_firestore/cloud_firestore.dart';

/// Review categories — mirrors iOS `ReviewCategory`.
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

/// Review types — mirrors iOS `ReviewType`.
enum ReviewType {
  general,
  buyer,
  renter,
  investor;

  String get label {
    switch (this) {
      case ReviewType.general:
        return 'General';
      case ReviewType.buyer:
        return 'Buyer';
      case ReviewType.renter:
        return 'Renter';
      case ReviewType.investor:
        return 'Investor';
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
      switch ((value as String? ?? '').toLowerCase()) {
        case 'buyer':
          return ReviewType.buyer;
        case 'renter':
          return ReviewType.renter;
        case 'investor':
          return ReviewType.investor;
        default:
          return ReviewType.general;
      }
    }

    Map<ReviewCategory, int> parseCategoryRatings(dynamic value) {
      if (value is! Map) return {};
      final out = <ReviewCategory, int>{};
      for (final entry in value.entries) {
        final key = entry.key as String? ?? '';
        final val = (entry.value as num?)?.toInt() ?? 0;
        for (final cat in ReviewCategory.values) {
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
    final catMap = <String, int>{};
    for (final entry in categoryRatings.entries) {
      catMap[entry.key.name] = entry.value;
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
      'reviewType': reviewType.name,
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
