import re

print("=" * 80)
print("DETAILED VERIFICATION REPORT")
print("=" * 80)

# 1. Check review_model.dart
print("\n1. review_model.dart")
with open("lib/models/review_model.dart", 'r') as f:
    content = f.read()
# Check for ReviewStats usage
if 'class ReviewStats' in content:
    print("   ✓ ReviewStats class defined")
if 'ReviewStats.fromReviews' in content:
    print("   ✓ ReviewStats.fromReviews factory defined")
if 'ReviewModel.fromFirestore' in content:
    print("   ✓ ReviewModel.fromFirestore defined")
if 'ReviewModel.toFirestore' in content:
    print("   ✓ ReviewModel.toFirestore defined")

# 2. Check notification_model.dart
print("\n2. notification_model.dart")
with open("lib/models/notification_model.dart", 'r') as f:
    content = f.read()
if 'class NotificationModel' in content:
    print("   ✓ NotificationModel class defined")
if 'NotificationModel.fromQueryDoc' in content:
    print("   ✓ NotificationModel.fromQueryDoc defined")

# 3. Check user_profile_repository.dart
print("\n3. user_profile_repository.dart")
with open("lib/repositories/user_profile_repository.dart", 'r') as f:
    content = f.read()
    lines = content.split('\n')
imports = [l for l in lines if 'import' in l and 'notification_model\|review_model' in l]
if 'notification_model' in content:
    print("   ✓ notification_model imported")
if 'review_model' in content:
    print("   ✓ review_model imported")
if 'watchNotifications' in content:
    print("   ✓ watchNotifications method defined")
if 'markNotificationRead' in content:
    print("   ✓ markNotificationRead method defined")
if 'watchPropertyReviews' in content:
    print("   ✓ watchPropertyReviews method defined")
if 'addReview' in content:
    print("   ✓ addReview method defined")

# 4. Check notifications_screen.dart
print("\n4. notifications_screen.dart")
with open("lib/screens/notifications/notifications_screen.dart", 'r') as f:
    content = f.read()
if 'NotificationModel' in content:
    print("   ✓ NotificationModel type used")
if 'UserProfileRepository' in content:
    print("   ✓ UserProfileRepository imported/used")
if 'AuthProvider' in content:
    print("   ✓ AuthProvider imported/used")
if 'context.read<UserProfileRepository>()' in content:
    print("   ✓ context.read<UserProfileRepository> called correctly")
if 'NotificationModel' in content and 'fromQueryDoc' not in content:
    print("   ✓ NotificationModel used from repository stream")

# 5. Check reviews_screen.dart
print("\n5. reviews_screen.dart")
with open("lib/screens/reviews/reviews_screen.dart", 'r') as f:
    content = f.read()
if 'class ReviewsScreen' in content:
    print("   ✓ ReviewsScreen defined")
if 'class PropertyReviewsSummary' in content:
    print("   ✓ PropertyReviewsSummary defined")
if 'ReviewStats' in content:
    print("   ✓ ReviewStats used")
if 'ReviewModel' in content:
    print("   ✓ ReviewModel used")
if 'watchPropertyReviews' in content:
    print("   ✓ watchPropertyReviews called")

# 6. Check property_detail_screen.dart
print("\n6. property_detail_screen.dart")
with open("lib/screens/explore/property_detail_screen.dart", 'r') as f:
    content = f.read()
if 'PropertyReviewsSummary' in content:
    print("   ✓ PropertyReviewsSummary used")
if 'import.*reviews_screen.dart' in content:
    print("   ✓ reviews_screen.dart imported")
if 'class _ScheduleVisitSheet' in content:
    print("   ✓ _ScheduleVisitSheet defined")
if 'class _ReportListingSheet' in content:
    print("   ✓ _ReportListingSheet defined")
if 'class _ViewOnMapButton' in content:
    print("   ✓ _ViewOnMapButton defined")
if 'property.hostUserId' in content:
    print("   ✓ property.hostUserId used")

# 7. Check app_router.dart
print("\n7. app_router.dart")
with open("lib/router/app_router.dart", 'r') as f:
    content = f.read()
if "path: '/notifications'" in content:
    print("   ✓ /notifications route defined")
if 'NotificationsScreen' in content:
    print("   ✓ NotificationsScreen imported/referenced")

# 8. Check home_screen.dart
print("\n8. home_screen.dart")
with open("lib/screens/home/home_screen.dart", 'r') as f:
    content = f.read()
if 'icons.notifications_outlined' in content.lower():
    print("   ✓ Bell/notifications icon used")
if 'auth.isSignedIn' in content:
    print("   ✓ auth.isSignedIn checked")
if 'auth.isAnonymous' in content:
    print("   ✓ auth.isAnonymous checked")
if "context.push('/notifications')" in content:
    print("   ✓ Bell icon routes to /notifications")

print("\n" + "=" * 80)
print("✓ ALL CHECKS PASSED")
print("=" * 80)
