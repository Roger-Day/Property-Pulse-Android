import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/property_model.dart';
import '../../repositories/property_repository.dart';
import '../../widgets/property_card.dart';

/// Mirrors iOS `HomeSeeAllListView` — full scrollable list for each home section.
enum HomeSeeAllDestination {
  featured,
  mostViewed,
  recentlyAdded,
  nearby,
  airbnbStays,
  all;

  String get title {
    switch (this) {
      case HomeSeeAllDestination.featured:
        return 'Featured Properties';
      case HomeSeeAllDestination.mostViewed:
        return 'Most Viewed Properties';
      case HomeSeeAllDestination.recentlyAdded:
        return 'Recently Added';
      case HomeSeeAllDestination.nearby:
        return 'Nearby Properties';
      case HomeSeeAllDestination.airbnbStays:
        return 'Short Stays';
      case HomeSeeAllDestination.all:
        return 'All Properties';
    }
  }

  String get emptyMessage {
    switch (this) {
      case HomeSeeAllDestination.featured:
        return 'Featured listings will appear here once they\'re loaded.';
      case HomeSeeAllDestination.mostViewed:
        return 'Popular properties will appear here once they receive views.';
      case HomeSeeAllDestination.recentlyAdded:
        return 'New properties will appear here as they\'re added.';
      case HomeSeeAllDestination.nearby:
        return 'Enable location services to see properties near you.';
      case HomeSeeAllDestination.airbnbStays:
        return 'No short-stay listings available right now.';
      case HomeSeeAllDestination.all:
        return 'Check back later for new listings.';
    }
  }

  IconData get emptyIcon {
    switch (this) {
      case HomeSeeAllDestination.featured:
        return Icons.star;
      case HomeSeeAllDestination.mostViewed:
        return Icons.visibility;
      case HomeSeeAllDestination.recentlyAdded:
        return Icons.access_time;
      case HomeSeeAllDestination.nearby:
        return Icons.location_on;
      case HomeSeeAllDestination.airbnbStays:
        return Icons.house;
      case HomeSeeAllDestination.all:
        return Icons.apartment;
    }
  }
}

class HomeSeeAllScreen extends StatelessWidget {
  const HomeSeeAllScreen({
    super.key,
    required this.destination,
    this.city,
    this.state,
  });

  final HomeSeeAllDestination destination;
  final String? city;
  final String? state;

  Stream<List<PropertyModel>> _stream(PropertyRepository repo) {
    switch (destination) {
      case HomeSeeAllDestination.featured:
      case HomeSeeAllDestination.recentlyAdded:
      case HomeSeeAllDestination.all:
        return repo.watchHomePropertyPool();
      case HomeSeeAllDestination.mostViewed:
        return repo.watchMostViewedListings();
      case HomeSeeAllDestination.nearby:
        return repo.watchNearbyListings(city: city, state: state);
      case HomeSeeAllDestination.airbnbStays:
        return repo.watchAirbnbListings();
    }
  }

  List<PropertyModel> _filter(
      List<PropertyModel> all, HomeSeeAllDestination dest) {
    switch (dest) {
      case HomeSeeAllDestination.featured:
        final featured = all
            .where((p) =>
                !p.deleted &&
                p.isCurrentlyFeatured &&
                p.hasListingImages)
            .toList();
        if (featured.isNotEmpty) return featured;
        return all.where((p) => !p.deleted && p.hasListingImages).toList();
      case HomeSeeAllDestination.recentlyAdded:
        return all.where((p) => !p.deleted).toList();
      case HomeSeeAllDestination.mostViewed:
      case HomeSeeAllDestination.nearby:
      case HomeSeeAllDestination.airbnbStays:
      case HomeSeeAllDestination.all:
        return all.where((p) => !p.deleted).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PropertyRepository>();

    return Scaffold(
      appBar: AppBar(title: Text(destination.title)),
      body: StreamBuilder<List<PropertyModel>>(
        stream: _stream(repo),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Error: ${snap.error}',
                  style:
                      TextStyle(color: AppColors.textSecondary)),
            );
          }
          final all = snap.data ?? [];
          final filtered = _filter(all, destination);
          if (filtered.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(destination.emptyIcon,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      destination.emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final p = filtered[i];
              return PropertyCard(
                property: p,
                onTap: () => context.push('/property/${p.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
