import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../providers/user_role_provider.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/phone_sign_in_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/onboarding/welcome_screen.dart';
import '../screens/explore/property_detail_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/home/developments_browse_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/projects/development_inventory_screen.dart';
import '../screens/projects/development_team_screen.dart';
import '../screens/projects/edit_development_screen.dart';
import '../screens/projects/project_detail_screen.dart';
import '../screens/projects/project_leads_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/messages/conversation_screen.dart';
import '../screens/messages/messages_screen.dart';
import '../screens/messages/new_message_screen.dart';
import '../screens/profile/app_settings_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/region_picker_screen.dart';
import '../screens/profile/appointments_screen.dart';
import '../screens/profile/change_password_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/identity_verification_screen.dart';
import '../screens/profile/verification_details_screen.dart';
import '../screens/profile/appointment_scheduling_screen.dart';
import '../screens/profile/create_listing_entry_screen.dart';
import '../screens/host/airbnb_host_workspace_screen.dart';
import '../screens/host/airbnb_listing_wizard_screen.dart';
import '../screens/profile/public_profile_screen.dart';
import '../screens/profile/my_developments_screen.dart';
import '../screens/profile/add_property_screen.dart';
import '../screens/profile/boost_listing_screen.dart';
import '../screens/profile/edit_property_screen.dart';
import '../screens/profile/my_listings_screen.dart';
import '../models/host_booking_row.dart';
import '../models/property_model.dart';
import '../screens/profile/guest_stay_detail_screen.dart';
import '../screens/profile/my_stays_screen.dart';
import '../screens/profile/notifications_settings_screen.dart';
import '../screens/profile/admin_application_form_screen.dart';
import '../screens/profile/apply_admin_screen.dart';
import '../screens/profile/customer_dashboard_screen.dart';
import '../screens/profile/developer_dashboard_screen.dart';
import '../screens/profile/host_dashboard_screen.dart';
import '../screens/profile/invite_realtor_screen.dart';
import '../screens/profile/activity_screen.dart';
import '../screens/profile/analytics_screen.dart';
import '../screens/profile/market_intelligence_screen.dart';
import '../screens/profile/performance_dashboard_screen.dart';
import '../screens/profile/premium_screen.dart';
import '../screens/profile/privacy_settings_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/data_export_screen.dart';
import '../screens/profile/about_property_pulse_screen.dart';
import '../screens/profile/support_screen.dart';
import '../screens/profile/viewing_history_screen.dart';
import '../screens/saved/saved_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/realtor/realtor_analytics_screen.dart';
import '../screens/realtor/realtor_lead_management_screen.dart';

/// iOS-style horizontal slide for profile stack pushes (parity with iPhone).
Page<void> _profileCupertinoPage(GoRouterState state, Widget child) =>
    CupertinoPage<void>(key: state.pageKey, child: child);

GoRouter createAppRouter(
  AuthProvider authProvider,
  UserRoleProvider userRoleProvider,
  OnboardingProvider onboardingProvider,
) {
  final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: Listenable.merge([
      authProvider,
      userRoleProvider,
      onboardingProvider,
    ]),
    redirect: (BuildContext context, GoRouterState state) {
      final loc = state.matchedLocation;

      if (authProvider.initializing) {
        if (loc == '/splash') return null;
        return '/splash';
      }

      if (!authProvider.isSignedIn) {
        // Always allow these unauthenticated routes through.
        // /welcome is the landing page (mirrors iOS EnhancedWelcomeView).
        // /onboarding is reached via the welcome screen's "Get Started" button.
        if (loc == '/welcome' || loc == '/onboarding') return null;
        if (loc == '/auth' || loc.startsWith('/auth/')) return null;
        // Everything else redirects to the animated welcome landing.
        return '/welcome';
      }

      if (loc.startsWith('/admin')) {
        if (userRoleProvider.adminRoleResolved &&
            !userRoleProvider.isAdmin) {
          return '/home';
        }
      }

      // Anonymous users tapping "Sign In" should reach /auth — don't redirect them away.
      if (authProvider.isAnonymous &&
          (loc == '/auth' || loc.startsWith('/auth/'))) {
        return null;
      }

      if (loc == '/splash' ||
          loc == '/welcome' ||
          loc == '/auth' ||
          loc.startsWith('/auth/') ||
          loc == '/onboarding') {
        return '/home';
      }
      // NOTE: '/explore' is NOT listed here — its own route-level redirect to
      // '/search' handles it.  Adding it here would intercept before the
      // route-level redirect fires and would incorrectly send the user to
      // '/home' instead of '/search'.
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const SignInScreen(),
        routes: [
          GoRoute(
            path: 'forgot',
            builder: (context, state) => const ForgotPasswordScreen(),
          ),
          GoRoute(
            path: 'phone',
            builder: (context, state) => const PhoneSignInScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/explore',
        redirect: (_, __) => '/search',
      ),
      GoRoute(
        path: '/saved',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SavedScreen(),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // ── Shared detail routes (outside the shell) ────────────────────────────
      // Placing these at the top level guarantees they are pushed ABOVE the
      // shell when called from any branch via context.push.  This means:
      //  • No tab-switching side-effect when navigating to detail pages.
      //  • The system back button always returns to the originating tab/screen.
      //  • The bottom NavigationBar is hidden on detail pages (correct Android UX).
      GoRoute(
        path: '/property/:propertyId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PropertyDetailScreen(
          propertyId: state.pathParameters['propertyId']!,
        ),
      ),
      // Mirrors iOS `propertypulse://appointment/{id}` deep link
      // (`DeepLinkManager.generateAppointmentURL`).
      GoRoute(
        path: '/appointment/:appointmentId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => AppointmentsRoleRouter(
          userId: authProvider.user!.uid,
          initialAppointmentId: state.pathParameters['appointmentId'],
        ),
      ),
      GoRoute(
        path: '/development/:projectId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ProjectDetailScreen(
          projectId: state.pathParameters['projectId']!,
        ),
        routes: [
          GoRoute(
            path: 'leads',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) {
              final pid = state.pathParameters['projectId']!;
              final name = state.extra as String? ?? 'Project';
              return ProjectLeadsScreen(projectId: pid, projectName: name);
            },
          ),
          GoRoute(
            path: 'inventory',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => DevelopmentInventoryScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: 'team',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => DevelopmentTeamScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => EditDevelopmentScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/user/:userId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PublicProfileScreen(
          userId: state.pathParameters['userId']!,
        ),
      ),
      GoRoute(
        path: '/realtor/analytics/:propertyId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return RealtorAnalyticsGateScreen(
            property: extra['property'] as PropertyModel,
            isProOrElite: extra['isProOrElite'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/realtor/leads',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final isProOrElite = state.extra as bool? ?? false;
          return RealtorLeadManagementScreen(isProOrElite: isProOrElite);
        },
      ),
      // Same pattern as /property/:id — conversation must be a top-level route
      // so pushes from property detail (outside the tab shell) resolve and open
      // the thread full-screen; nested shell routes alone can fail to match.
      GoRoute(
        path: '/messages/thread/:threadId',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) {
          if (!authProvider.isSignedIn || authProvider.user == null) {
            return '/auth';
          }
          return null;
        },
        builder: (context, state) => ConversationScreen(
          threadId: state.pathParameters['threadId']!,
          currentUserId: authProvider.user!.uid,
        ),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'developments',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const DevelopmentsBrowseScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'browse',
                    redirect: (_, __) => '/search',
                  ),
                  // Redirect legacy shell-internal paths to the shared top-level
                  // routes so existing deep links / bookmarks continue to work.
                  GoRoute(
                    path: 'property/:propertyId',
                    redirect: (_, state) =>
                        '/property/${state.pathParameters['propertyId']}',
                  ),
                  GoRoute(
                    path: 'user/:userId',
                    redirect: (_, state) =>
                        '/user/${state.pathParameters['userId']}',
                  ),
                  GoRoute(
                    path: 'development/:projectId',
                    redirect: (_, state) =>
                        '/development/${state.pathParameters['projectId']}',
                    routes: [
                      GoRoute(
                        path: 'leads',
                        redirect: (_, state) =>
                            '/development/${state.pathParameters['projectId']}/leads',
                      ),
                      GoRoute(
                        path: 'inventory',
                        redirect: (_, state) =>
                            '/development/${state.pathParameters['projectId']}/inventory',
                      ),
                      GoRoute(
                        path: 'team',
                        redirect: (_, state) =>
                            '/development/${state.pathParameters['projectId']}/team',
                      ),
                      GoRoute(
                        path: 'edit',
                        redirect: (_, state) =>
                            '/development/${state.pathParameters['projectId']}/edit',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/messages',
                builder: (context, state) => const MessagesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const NewMessageScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'my-listings',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      MyListingsScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  // Nested (not top-level) so the bottom nav bar stays visible —
                  // matches iOS CreateListingEntryView, which has no
                  // .toolbar(.hidden, for: .tabBar) and is pushed within the
                  // tab's own NavigationStack.
                  GoRoute(
                    path: 'add-listing',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      CreateListingEntryScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'edit-listing/:propertyId',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      EditPropertyScreen(
                        propertyId: state.pathParameters['propertyId']!,
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'boost-listing/:propertyId',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      BoostListingScreen(
                        propertyId: state.pathParameters['propertyId']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'my-stays/detail',
                    pageBuilder: (context, state) {
                      final extra = state.extra;
                      if (extra is! HostBookingRow) {
                        return MaterialPage<void>(
                          key: state.pageKey,
                          child: Scaffold(
                            appBar: AppBar(title: const Text('Stay')),
                            body: const Center(
                              child: Text('Unable to open stay'),
                            ),
                          ),
                        );
                      }
                      return _profileCupertinoPage(
                        state,
                        GuestStayDetailScreen(booking: extra),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'my-stays',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      MyStaysScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'my-developments',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      MyDevelopmentsScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'customer-dashboard',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      CustomerDashboardScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'edit-profile',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      EditProfileScreen(
                        userId: authProvider.user!.uid,
                        email: authProvider.user!.email ?? '—',
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'identity-verification',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      VerificationDetailsScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'notifications',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      NotificationsSettingsScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      SettingsScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'region',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      RegionPickerScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'appointments',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      AppointmentsRoleRouter(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'schedule',
                        pageBuilder: (context, state) => _profileCupertinoPage(
                          state,
                          const AppointmentSchedulingScreen(),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'change-password',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const ChangePasswordScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'privacy-settings',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      PrivacySettingsScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'premium',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const PremiumScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'analytics',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      AnalyticsScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'market-intelligence',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      MarketIntelligenceScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'activity',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      ActivityScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'performance',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const PerformanceDashboardScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'host-dashboard',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      AirbnbHostWorkspaceScreen(
                        hostId: authProvider.user!.uid,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'create-listing',
                        pageBuilder: (context, state) => _profileCupertinoPage(
                          state,
                          const AirbnbListingWizardScreen(),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'developer-dashboard',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const DeveloperDashboardScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'invite-realtor',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const InviteRealtorScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'apply-admin',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const ApplyAdminScreen(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'form',
                        pageBuilder: (context, state) => _profileCupertinoPage(
                          state,
                          const AdminApplicationFormScreen(),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'viewing-history',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      ViewingHistoryScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'data-export',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      DataExportScreen(
                        userId: authProvider.user!.uid,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'about',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const AboutPropertyPulseScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'support',
                    pageBuilder: (context, state) => _profileCupertinoPage(
                      state,
                      const SupportScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminDashboardScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
