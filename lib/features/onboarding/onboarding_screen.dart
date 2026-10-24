import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/widgets/gradient_button.dart';

/// 6-page onboarding tutorial shown on first app launch.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingData(
      icon: Icons.auto_awesome,
      title: 'See Your Outfit on AI Models',
      description:
          'Upload any clothing and let AI create realistic virtual outfits.',
      color: Color(0xFF22C55E),
    ),
    _OnboardingData(
      icon: Icons.checkroom_rounded,
      title: 'Virtually Try On Clothes',
      description:
          'Upload your own photo and see how every outfit looks before buying.',
      color: Color(0xFF10B981),
    ),
    _OnboardingData(
      icon: Icons.auto_fix_high,
      title: 'Realistic AI Editing',
      description:
          'Powerful AI replaces clothes naturally while keeping your pose and body.',
      color: Color(0xFF059669),
    ),
    _OnboardingData(
      icon: Icons.person_outline_rounded,
      title: 'See It On You',
      description: 'Generate highly realistic outfit previews within seconds.',
      color: Color(0xFF34D399),
    ),
    _OnboardingData(
      icon: Icons.speed_rounded,
      title: 'Instant Try Before You Buy',
      description: 'Never guess how clothes fit again.',
      color: Color(0xFF6EE7B7),
    ),
    _OnboardingData(
      icon: Icons.rocket_launch_rounded,
      title: 'Start Creating',
      description: 'Login and receive 5 free AI generations.',
      color: Color(0xFF4ADE80),
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _completeOnboarding() async {
    // Set onboarding flag in storage
    await ref.read(storageServiceProvider).setOnboardingSeen();

    // Force provider invalidation to sync the new storage value
    // This ensures hasSeenOnboardingProvider reflects the updated state
    ref.invalidate(storageServiceProvider);

    // Small delay to ensure provider state update propagates
    await Future.delayed(const Duration(milliseconds: 100));

    // Now GoRouter's redirect will see hasSeenOnboarding=true
    // and route appropriately (login if not logged in)
    if (mounted) context.go('/login');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return _OnboardingPage(data: page, isDark: isDark);
                },
              ),
            ),

            // Page indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: SmoothPageIndicator(
                controller: _pageController,
                count: _pages.length,
                effect: ExpandingDotsEffect(
                  activeDotColor: AppColors.primary,
                  dotColor: isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider,
                  dotHeight: 8,
                  dotWidth: 8,
                  expansionFactor: 4,
                  spacing: 6,
                ),
              ),
            ),

            // Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: GradientButton(
                text: _currentPage == _pages.length - 1
                    ? 'Get Started'
                    : 'Next',
                icon: _currentPage == _pages.length - 1
                    ? Icons.arrow_forward_rounded
                    : null,
                onPressed: _nextPage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingData {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingData data;
  final bool isDark;

  const _OnboardingPage({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration container
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  data.color.withValues(alpha: 0.2),
                  data.color.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: data.color.withValues(alpha: 0.15),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Icon(data.icon, size: 80, color: data.color),
          ),
          const SizedBox(height: 48),

          // Title
          Text(
            data.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            data.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
