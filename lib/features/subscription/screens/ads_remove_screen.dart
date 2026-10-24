import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_providers.dart';

/// A dedicated full-screen page that shows the "Remove Ads 1 Month"
/// subscription pack ($4.99 for 1 month).
///
/// Integrated with official Google Play Billing via [SubscriptionService].
class AdsRemoveScreen extends ConsumerStatefulWidget {
  const AdsRemoveScreen({super.key});

  @override
  ConsumerState<AdsRemoveScreen> createState() => _AdsRemoveScreenState();
}

class _AdsRemoveScreenState extends ConsumerState<AdsRemoveScreen> {
  bool _isPurchasing = false;
  bool _isRestoring = false;

  Future<void> _purchaseSubscription() async {
    setState(() => _isPurchasing = true);
    try {
      final service = ref.read(subscriptionServiceProvider);
      if (!service.isAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google Play Billing service is initializing or unavailable on this device.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final success = await service.purchaseSubscription();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not launch Google Play checkout. Please check Google Play Store connection.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isRestoring = true);
    try {
      final service = ref.read(subscriptionServiceProvider);
      await service.restorePurchases();
      if (mounted) {
        final isAdFree = ref.read(isAdFreeProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAdFree
                  ? '✓ Active 1-Month Ad-Free pack restored!'
                  : 'No active Google Play purchase found for this account.',
            ),
            backgroundColor: isAdFree ? Colors.green.shade600 : null,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdFree = ref.watch(isAdFreeProvider);
    final subscriptionService = ref.watch(subscriptionServiceProvider);
    final displayPrice = subscriptionService.displayPrice;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Ad-Free Pass'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // ── Hero Banner ──
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ── Title & Value Pill ──
              Text(
                isAdFree ? 'You Are 100% Ad-Free!' : 'Remove All Ads for 1 Month',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                isAdFree
                    ? 'Your 1-month VIP pass is active. Enjoy uninterrupted virtual try-on!'
                    : 'Transform your fitting room into a fast, ad-free studio for 1 month.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),

              // ── Main Pass Card ──
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: isDark
                      ? LinearGradient(
                          colors: [
                            const Color(0xFF1E1B4B).withValues(alpha: 0.8),
                            const Color(0xFF18181B),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFEEF2FF), Colors.white],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Badge: BEST VALUE
                    if (!isAdFree)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(22),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'SPECIAL OFFER • 1 MONTH PASS • 100% AD-FREE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          // Status Row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (isAdFree
                                          ? AppColors.success
                                          : const Color(0xFF6366F1))
                                      .withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isAdFree
                                      ? Icons.check_circle_rounded
                                      : Icons.auto_awesome_rounded,
                                  color: isAdFree
                                      ? AppColors.success
                                      : const Color(0xFF6366F1),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isAdFree ? 'VIP Ad-Free Active' : '1-Month Ad-Free Pack',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      isAdFree
                                          ? 'All ads removed across the app'
                                          : 'Monthly pass with Google Play',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: isDark
                                                ? AppColors.darkTextTertiary
                                                : AppColors.lightTextTertiary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isAdFree)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          if (!isAdFree) ...[
                            const SizedBox(height: 20),
                            const Divider(height: 1),
                            const SizedBox(height: 20),

                            // Price presentation
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  displayPrice,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: isDark ? Colors.white : Colors.black87,
                                        letterSpacing: -1,
                                      ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'for 1 Month',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF6366F1),
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),

                            // Equivalent price
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Renews monthly • Cancel anytime in Play Store',
                                style: TextStyle(
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),

                            // Google Play Billing Checkout Button
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isPurchasing ? null : _purchaseSubscription,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isPurchasing
                                    ? const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Connecting to Google Play...',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.shopping_bag_rounded, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Get 1 Month Ad-Free — $displayPrice',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),

                          // Restore button
                          TextButton.icon(
                            onPressed: _isRestoring ? null : _restorePurchases,
                            icon: _isRestoring
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.restore_rounded, size: 18),
                            label: Text(
                              _isRestoring ? 'Checking Play Store...' : 'Restore Existing Purchase',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── What's Included ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDark ? AppColors.darkDivider : AppColors.lightDivider)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What is included in this pack:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _benefitRow(
                      icon: Icons.block_rounded,
                      title: '100% Zero Ads',
                      subtitle: 'No full-screen interstitial popups and no bottom banners anywhere in the app.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    _benefitRow(
                      icon: Icons.flash_on_rounded,
                      title: 'Instant Priority Try-On',
                      subtitle: 'Generate outfits immediately without waiting for rewarded ads or countdowns.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    _benefitRow(
                      icon: Icons.date_range_rounded,
                      title: '1 Full Month of Coverage',
                      subtitle:
                          '30 days of unlimited try-on sessions without any ads or countdowns.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    _benefitRow(
                      icon: Icons.security_rounded,
                      title: 'Google Play Protected',
                      subtitle: 'Secure checkout and instant restore anytime you change or reset your phone.',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Disclaimer ──
              Text(
                'Payment will be charged to your Google Play account at confirmation of purchase. Managed directly via Google Play Subscriptions.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benefitRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF6366F1)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
