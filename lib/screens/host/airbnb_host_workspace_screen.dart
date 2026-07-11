import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_colors.dart';
import 'host_calendar_screen.dart';
import 'host_earnings_screen.dart';
import 'host_reservations_screen.dart';

/// Mirrors iOS `AirbnbHostWorkspaceView` — central hub for Airbnb host tools.
class AirbnbHostWorkspaceScreen extends StatelessWidget {
  const AirbnbHostWorkspaceScreen({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Workspace'),
        actions: [
          TextButton.icon(
            onPressed: () =>
                context.push('/profile/host-dashboard/create-listing'),
            icon: const Icon(Icons.add),
            label: const Text('New Listing'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick stats header
          _HostWorkspaceHeader(hostId: hostId),
          const SizedBox(height: 20),
          const Text(
            'Management Tools',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Action cards
          _WorkspaceCard(
            icon: Icons.calendar_month,
            color: Colors.blue,
            title: 'Calendar',
            subtitle: 'Manage availability and blocked dates',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HostCalendarScreen(hostId: hostId),
            )),
          ),
          const SizedBox(height: 10),
          _WorkspaceCard(
            icon: Icons.book_online,
            color: Colors.teal,
            title: 'Reservations',
            subtitle: 'View and manage all bookings',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HostReservationsScreen(hostId: hostId),
            )),
          ),
          const SizedBox(height: 10),
          _WorkspaceCard(
            icon: Icons.attach_money,
            color: Colors.green,
            title: 'Earnings',
            subtitle: 'Track payouts and revenue',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HostEarningsScreen(hostId: hostId),
            )),
          ),
          const SizedBox(height: 24),
          // Tips section
          _HostTipsCard(),
        ],
      ),
    );
  }
}

class _HostWorkspaceHeader extends StatelessWidget {
  const _HostWorkspaceHeader({required this.hostId});
  final String hostId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white24,
            radius: 28,
            child: Icon(Icons.house, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Airbnb Host',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage your short-term rentals',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _HostTipsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tips = [
      'Keep your calendar up-to-date to avoid double bookings.',
      'Respond to booking requests within 24 hours for better rankings.',
      'Add high-quality photos to increase booking rates.',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.amber, size: 18),
              SizedBox(width: 6),
              Text('Host Tips',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          ...tips.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.amber)),
                  Expanded(
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
