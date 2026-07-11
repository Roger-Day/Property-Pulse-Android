import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connectivity_service.dart';

/// Mirrors iOS `.offlineBanner()` modifier — shows a sticky banner at the top
/// of the screen when the device is offline, hiding automatically on reconnect.
///
/// Wrap any top-level scaffold body with this widget:
/// ```dart
/// body: OfflineBanner(child: myContent),
/// ```
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _heightAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heightAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivity, _) {
        // Animate banner in/out
        if (!connectivity.isOnline) {
          _ctrl.forward();
        } else {
          _ctrl.reverse();
        }

        return Column(
          children: [
            // Animated offline banner
            SizeTransition(
              sizeFactor: _heightAnim,
              axisAlignment: -1,
              child: _OfflineBannerBar(
                onReconnect: () {
                  // Could trigger a refresh here
                },
              ),
            ),
            // Main content
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

class _OfflineBannerBar extends StatelessWidget {
  const _OfflineBannerBar({required this.onReconnect});
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1C1C1E), // iOS dark offline colour
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 16),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "You're offline — showing cached content",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
