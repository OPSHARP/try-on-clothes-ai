import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/screens/main_shell.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/try_on/screens/result_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/legal/screens/privacy_policy_screen.dart';
import '../../features/legal/screens/terms_of_service_screen.dart';
import '../../features/subscription/screens/ads_remove_screen.dart';

/// GoRouter configuration.
///
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      // Allow splash to complete its animation, then router takes over
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // ── Subscription Screen (before ShellRoute to avoid routing conflicts) ──
      GoRoute(
        path: '/ads-remove',
        builder: (context, state) => const AdsRemoveScreen(),
      ),

      // ── Main App Shell with Bottom Nav ──
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HistoryScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
          ),
        ],
      ),

      // ── Feature Screens ──
      GoRoute(
        path: '/try-on',
        redirect: (context, state) => '/home',
      ),
      GoRoute(
        path: '/result',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ResultScreen(
            personImagePath: extra?['personImage'] ?? '',
            clothesImagePath: extra?['clothesImage'] ?? '',
            resultImagePath: extra?['resultImage'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      // ── Legal Pages ──
      GoRoute(
        path: '/legal/privacy-policy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/legal/terms-of-service',
        builder: (context, state) => const TermsOfServiceScreen(),
      ),
    ],
  );
});
