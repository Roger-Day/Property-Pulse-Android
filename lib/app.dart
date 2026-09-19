import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'constants/app_constants.dart';
import 'providers/theme_mode_provider.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'widgets/account_blocked_gate.dart';
import 'widgets/development_invite_prompt_gate.dart';
import 'widgets/in_app_notification_banner.dart';

class PropertyPulseApp extends StatefulWidget {
  const PropertyPulseApp({super.key, required this.router});

  final GoRouter router;

  @override
  State<PropertyPulseApp> createState() => _PropertyPulseAppState();
}

class _PropertyPulseAppState extends State<PropertyPulseApp> {
  final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();

  // Built once — ThemeData is a large immutable object; recreating it every
  // build() wastes CPU and causes unnecessary MaterialApp rebuilds.
  final ThemeData _lightTheme = buildPropertyPulseTheme(dark: false);
  final ThemeData _darkTheme = buildPropertyPulseTheme(dark: true);

  @override
  Widget build(BuildContext context) {
    final themeMode =
        context.select<ThemeModeNotifier, ThemeMode>((n) => n.themeMode);

    final lightTheme = _lightTheme;
    final darkTheme = _darkTheme;

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: widget.router,
      scaffoldMessengerKey: _scaffoldKey,
      builder: (context, child) {
        // ── 1. Text scale clamping ───────────────────────────────────────────
        // Clamp font scaling between 0.85× and 1.3× so extreme accessibility
        // settings don't break our carefully designed layouts.
        // iOS equivalent: .dynamicTypeSize(.large ... .accessibility3)
        // Android: user can set text size in display settings
        final mediaQuery = MediaQuery.of(context);
        final clampedTextScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.30,
        );

        // ── 2. In-app notification overlay ───────────────────────────────────
        // iOS: foreground FCM via banner card (not SnackBar)
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedTextScaler),
          child: AccountBlockedGate(
            navigatorKey: widget.router.routerDelegate.navigatorKey,
            child: DevelopmentInvitePromptGate(
              navigatorKey: widget.router.routerDelegate.navigatorKey,
              child: InAppNotificationOverlay(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}
