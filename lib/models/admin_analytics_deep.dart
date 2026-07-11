/// Mirrors iOS `AdminAnalyticsViewModel` aggregates (loaded client-side like iOS).
class WeeklyDataPoint {
  const WeeklyDataPoint({
    required this.weekLabel,
    required this.count,
    required this.startDate,
  });

  final String weekLabel;
  final int count;
  final DateTime startDate;
}

class StateDataPoint {
  const StateDataPoint({
    required this.state,
    required this.count,
    required this.percentage,
  });

  final String state;
  final int count;
  final double percentage;
}

class AdminAnalyticsDeep {
  const AdminAnalyticsDeep({
    required this.totalUsers,
    required this.totalProperties,
    required this.activeListings,
    required this.totalConversations,
    required this.openModerationReports,
    required this.weeklyUserData,
    required this.weeklyPropertyData,
    required this.userGrowthPercentage,
    required this.propertyGrowthPercentage,
    required this.propertyByState,
    required this.userByState,
    this.errorMessage,
  });

  final int totalUsers;
  final int totalProperties;
  final int activeListings;
  final int totalConversations;
  final int openModerationReports;

  final List<WeeklyDataPoint> weeklyUserData;
  final List<WeeklyDataPoint> weeklyPropertyData;

  /// Week-over-week growth approximating iOS `calculateGrowth`.
  final double userGrowthPercentage;
  final double propertyGrowthPercentage;

  final List<StateDataPoint> propertyByState;
  final List<StateDataPoint> userByState;

  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}
