import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/models/ai_provider_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../home/widgets/api_setup_guide_sheet.dart';

/// Merged Profile & Settings screen with app info, AI provider config,
/// subscription management, theme, and legal links.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Text editing controllers for API keys (one per provider)
  final Map<String, TextEditingController> _apiKeyControllers = {};
  final TextEditingController _endpointController = TextEditingController();

  bool _obscureApiKeys = true;

  @override
  void dispose() {
    for (final controller in _apiKeyControllers.values) {
      controller.dispose();
    }
    _endpointController.dispose();
    super.dispose();
  }

  /// Ensure a controller exists for the given provider and sync from storage.
  TextEditingController _controllerFor(String providerId) {
    if (!_apiKeyControllers.containsKey(providerId)) {
      final storage = ref.read(storageServiceProvider);
      final controller = TextEditingController(
        text: storage.providerApiKey(providerId),
      );
      _apiKeyControllers[providerId] = controller;
    }
    return _apiKeyControllers[providerId]!;
  }

  /// Save API key for the given provider.
  Future<void> _saveApiKey(String providerId) async {
    final controller = _controllerFor(providerId);
    final key = controller.text.trim();
    await ref.read(storageServiceProvider).setProviderApiKey(providerId, key);
    // Force the home-screen API key check to recompute so the banner
    // auto-hides the next time the home screen reads this provider.
    ref.invalidate(hasApiKeyForProviderProvider);
    // Invalidate the AI service factory so the Try On screen picks up the
    // new key immediately when it reads aiServiceProvider.
    ref.invalidate(aiServiceProvider);
    // Invalidate the configured providers list so the Try On screen's
    // provider selector picks up the change immediately.
    ref.invalidate(configuredProvidersProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            key.isEmpty
                ? 'API key cleared for ${AiProviderConfig.fromId(providerId)?.name ?? providerId}'
                : 'API key saved for ${AiProviderConfig.fromId(providerId)?.name ?? providerId}',
          ),
        ),
      );
    }
  }

  /// Open a URL in the browser.
  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
        title: const Column(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 48,
              color: AppColors.primary,
            ),
            SizedBox(height: 12),
            Text('Try On Clothes AI', textAlign: TextAlign.center),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Version 1.0.0 (Target API 36 • Android 16)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Play Billing 8.0+ • Flexible Updates • 16KB Aligned',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'AI-powered virtual fitting room application that lets you try on clothes virtually using advanced AI technology.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdFree = ref.watch(isAdFreeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final storage = ref.watch(storageServiceProvider);
    final currentProviderId = ref.watch(selectedProviderIdProvider);
    final currentConfig = ref.watch(selectedProviderConfigProvider);
    final currentLangCode = ref.watch(languageProvider);
    final currentLang = _supportedLanguages.firstWhere(
      (l) => l.code == currentLangCode,
      orElse: () => _supportedLanguages.first,
    );
    final currentMeta = _allProvidersMeta.firstWhere(
      (m) => m.id == currentProviderId,
      orElse: () => _allProvidersMeta.first,
    );
    final currentApiKey = storage.providerApiKey(currentProviderId);
    final isConfigured = currentApiKey.isNotEmpty;

    // Sync endpoint controller once
    if (_endpointController.text.isEmpty &&
        storage.customApiEndpoint.isNotEmpty) {
      _endpointController.text = storage.customApiEndpoint;
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Title ──
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Profile',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── App Info Card ──
              _buildAppInfoCard(context, isDark, isAdFree),
              const SizedBox(height: 20),

              // ── VIP 6-Month Ad-Free Pack Banner ──
              _buildSubscriptionBanner(context, isDark, isAdFree),
              const SizedBox(height: 24),

              // ── Appearance ──
              _sectionTitle('Appearance', isDark),
              const SizedBox(height: 8),
              _buildCard(
                isDark,
                children: [
                  _settingsTile(
                    context,
                    icon: Icons.dark_mode_rounded,
                    title: 'Dark Mode',
                    isDark: isDark,
                    trailing: Switch(
                      value: themeMode == 'dark',
                      onChanged: (value) {
                        ref
                            .read(themeModeProvider.notifier)
                            .setTheme(value ? 'dark' : 'light');
                      },
                      activeTrackColor: AppColors.primary,
                    ),
                  ),
                  _divider(isDark),
                  _settingsTile(
                    context,
                    icon: Icons.language_rounded,
                    title: 'Language',
                    subtitle:
                        '${currentLang.flag} ${currentLang.nativeName} (${currentLang.englishName})',
                    isDark: isDark,
                    onTap: () =>
                        _showLanguageSelector(context, currentLangCode, isDark),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── AI Provider ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionTitle('AI Provider', isDark),
                  TextButton.icon(
                    onPressed: () => ApiSetupGuideSheet.show(context),
                    icon: const Icon(Icons.help_outline_rounded, size: 16),
                    label: const Text(
                      'Setup Tutorial',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCard(
                isDark,
                children: [
                  // Modern Provider Selector Tile
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: InkWell(
                      onTap: () => _showProviderSelector(
                        context,
                        currentProviderId,
                        isDark,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: currentMeta.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              currentMeta.icon,
                              size: 20,
                              color: currentMeta.color,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        currentMeta.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1E2432),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: currentMeta.color
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        currentMeta.tag,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: currentMeta.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isConfigured
                                      ? '🟢 Active & Ready'
                                      : '🟡 API Key Required',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isConfigured
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFF59E0B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Change',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Show configuration for the selected provider
                  if (currentConfig != null) ...[
                    _divider(isDark),

                    // Get API Key link
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: InkWell(
                        onTap: currentConfig.signupUrl.isNotEmpty
                            ? () => _openUrl(currentConfig.signupUrl)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                              color: currentConfig.signupUrl.isNotEmpty
                                  ? AppColors.primary
                                  : (isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              currentConfig.signupUrl.isNotEmpty
                                  ? 'Get ${currentConfig.name} API Key'
                                  : 'Custom API — no signup needed',
                              style: TextStyle(
                                color: currentConfig.signupUrl.isNotEmpty
                                    ? AppColors.primary
                                    : (isDark
                                          ? AppColors.darkTextTertiary
                                          : AppColors.lightTextTertiary),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // API Key input
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controllerFor(currentProviderId),
                              obscureText: _obscureApiKeys,
                              decoration: InputDecoration(
                                labelText: currentConfig.apiKeyLabel,
                                hintText: currentConfig.apiKeyHint,
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureApiKeys
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(
                                      () => _obscureApiKeys = !_obscureApiKeys,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: () => _saveApiKey(currentProviderId),
                              style: ButtonStyle(
                                backgroundColor: WidgetStatePropertyAll(
                                  AppColors.primary,
                                ),
                                foregroundColor: WidgetStatePropertyAll(
                                  Colors.white,
                                ),
                                shape: WidgetStatePropertyAll(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                textStyle: WidgetStatePropertyAll(
                                  const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                padding: WidgetStatePropertyAll(
                                  const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                minimumSize: WidgetStatePropertyAll(
                                  const Size(64, 40),
                                ),
                              ),
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Custom endpoint URL field
                    if (currentConfig.requiresEndpoint) ...[
                      _divider(isDark),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _endpointController,
                                decoration: InputDecoration(
                                  labelText: 'API Endpoint URL',
                                  hintText: currentConfig.endpointHint,
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 44,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final url = _endpointController.text.trim();
                                  if (url.isEmpty) return;
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  // Validate the URL before saving
                                  final parsedUri = Uri.tryParse(url);
                                  if (parsedUri == null ||
                                      !parsedUri.hasScheme ||
                                      !parsedUri.hasAuthority) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Invalid URL. Must include scheme (https://) and host.',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }
                                  await ref
                                      .read(storageServiceProvider)
                                      .setCustomApiEndpoint(url);
                                  // Force the home-screen API-key check to
                                  // recompute (custom provider also requires
                                  // an endpoint).
                                  ref.invalidate(hasApiKeyForProviderProvider);
                                  // Invalidate the AI service factory so the
                                  // Try On screen picks up the new endpoint.
                                  ref.invalidate(aiServiceProvider);
                                  // Invalidate the configured providers list
                                  // so the Try On screen's provider selector
                                  // picks up the change immediately.
                                  ref.invalidate(configuredProvidersProvider);
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Endpoint URL saved'),
                                    ),
                                  );
                                },
                                style: ButtonStyle(
                                  backgroundColor: WidgetStatePropertyAll(
                                    AppColors.primary,
                                  ),
                                  foregroundColor: WidgetStatePropertyAll(
                                    Colors.white,
                                  ),
                                  shape: WidgetStatePropertyAll(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  textStyle: WidgetStatePropertyAll(
                                    const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  padding: WidgetStatePropertyAll(
                                    const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  minimumSize: WidgetStatePropertyAll(
                                    const Size(64, 40),
                                  ),
                                ),
                                child: const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // ── Preferences Menu ──
              _optionSection(
                title: 'Preferences',
                isDark: isDark,
                items: [
                  _optionItem(
                    context,
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    isDark: isDark,
                    onTap: () => context.push('/notifications'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Legal & Support ──
              _optionSection(
                title: 'Support',
                isDark: isDark,
                items: [
                  _optionItem(
                    context,
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    isDark: isDark,
                    onTap: () => context.push('/legal/privacy-policy'),
                  ),
                  _optionItem(
                    context,
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    isDark: isDark,
                    onTap: () => context.push('/legal/terms-of-service'),
                  ),
                  _optionItem(
                    context,
                    icon: Icons.system_update_rounded,
                    label: 'Check for Updates',
                    isDark: isDark,
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                    onTap: () {
                      final updateService =
                          ref.read(inAppUpdateServiceProvider);
                      updateService.checkForFlexibleUpdate(
                        context: context,
                        showFeedbackIfNoUpdate: true,
                      );
                    },
                  ),
                  _optionItem(
                    context,
                    icon: Icons.info_outline_rounded,
                    label: 'About App',
                    isDark: isDark,
                    trailing: Text(
                      'v${AppConstants.appVersion}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                    ),
                    onTap: () => _showAboutDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build Helpers ──

  Widget _buildAppInfoCard(BuildContext context, bool isDark, bool isAdFree) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (isDark ? AppColors.darkDivider : AppColors.lightDivider)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // App Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Try On Clothes AI',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Virtual Fitting Room',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _profileStat(
                context,
                icon: Icons.auto_awesome_rounded,
                value: 'Free',
                label: 'Plan',
                color: AppColors.primary,
              ),
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
              ),
              _profileStat(
                context,
                icon: isAdFree
                    ? Icons.verified_rounded
                    : Icons.visibility_rounded,
                value: isAdFree ? 'Ad-Free' : 'Ads Active',
                label: 'Status',
                color: isAdFree ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionBanner(
    BuildContext context,
    bool isDark,
    bool isAdFree,
  ) {
    if (isAdFree) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF064E3B), Color(0xFF047857)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF059669).withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF34D399),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VIP 6-Month Ad-Free Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'All interstitial & banner ads removed with Google Play.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => context.push('/ads-remove'),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Manage',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => context.push('/ads-remove'),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4338CA), Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Color(0xFFFBBF24),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REMOVE ALL ADS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '1-Month Special Pass • Play Billing',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '100% AD-FREE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '\$${AppConstants.subscriptionPriceUSD.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '/ 1 month',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Monthly Pass',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Enjoy instant try-on generation without interstitial, rewarded, or banner ads.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_open_rounded,
                    color: Color(0xFF4338CA),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Get 6-Month Ad-Free Pass',
                    style: TextStyle(
                      color: Color(0xFF4338CA),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF4338CA),
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileStat(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkTextTertiary
                : AppColors.lightTextTertiary,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: isDark
              ? AppColors.darkTextTertiary
              : AppColors.lightTextTertiary,
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? AppColors.darkDivider : AppColors.lightDivider)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(bool isDark) {
    return Divider(
      height: 0.5,
      indent: 56,
      color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
    );
  }

  Widget _settingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    bool? isDark,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final dark = isDark ?? Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: dark ? AppColors.darkIcon : AppColors.lightIcon,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: dark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: dark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _optionSection({
    required String title,
    required bool isDark,
    required List<Widget> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
            ),
          ),
        ],
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (isDark ? AppColors.darkDivider : AppColors.lightDivider)
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final isLast = entry.key == items.length - 1;
              return Column(
                children: [
                  entry.value,
                  if (!isLast)
                    Divider(
                      height: 0.5,
                      indent: 56,
                      color: isDark
                          ? AppColors.darkDivider
                          : AppColors.lightDivider,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _optionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isDark,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDark ? AppColors.darkIcon : AppColors.lightIcon,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (trailing != null)
              trailing
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
          ],
        ),
      ),
    );
  }

  void _showLanguageSelector(
    BuildContext context,
    String currentCode,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _supportedLanguages.where((lang) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return lang.englishName.toLowerCase().contains(q) ||
                  lang.nativeName.toLowerCase().contains(q) ||
                  lang.code.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B202E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Drag Handle
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Language',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1E2432),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: TextField(
                      onChanged: (val) {
                        setSheetState(() => searchQuery = val);
                      },
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1E2432),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search language...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF131722)
                            : const Color(0xFFF1F4FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (context, index) {
                        final lang = filtered[index];
                        final isSelected = lang.code == currentCode;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6342E8)
                                      .withValues(alpha: 0.15)
                                  : (isDark
                                      ? const Color(0xFF131722)
                                      : const Color(0xFFF1F4FA)),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                lang.flag,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                          title: Text(
                            lang.nativeName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? const Color(0xFF6342E8)
                                  : (isDark
                                      ? Colors.white
                                      : const Color(0xFF1E2432)),
                            ),
                          ),
                          subtitle: Text(
                            lang.englishName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF8B98AF),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF6342E8),
                                  size: 22,
                                )
                              : null,
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            await ref
                                .read(languageProvider.notifier)
                                .setLanguage(lang.code);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Language set to ${lang.nativeName} (${lang.englishName})',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: const Color(0xFF6342E8),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showProviderSelector(
      BuildContext context, String currentId, bool isDark) {
    HapticFeedback.lightImpact();
    final storage = ref.read(storageServiceProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _allProvidersMeta.where((p) {
              final q = searchQuery.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.description.toLowerCase().contains(q) ||
                  p.tag.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B202E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Virtual Try-On Providers',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E2432),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Select your AI garment synthesis backend',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF8B98AF),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: TextField(
                      onChanged: (val) {
                        setSheetState(() => searchQuery = val);
                      },
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1E2432),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search provider (Fashn, Fal, Replicate...)...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF131722)
                            : const Color(0xFFF1F4FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (context, index) {
                        final provider = filtered[index];
                        final isSelected = provider.id == currentId;
                        final key = storage.providerApiKey(provider.id);
                        final hasKey = key.isNotEmpty;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: provider.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              provider.icon,
                              color: provider.color,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                provider.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1E2432),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: provider.color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  provider.tag,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: provider.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  provider.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      hasKey
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.vpn_key_outlined,
                                      size: 13,
                                      color: hasKey
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      hasKey
                                          ? 'Configured & Ready'
                                          : 'API Key Required',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: hasKey
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF6342E8),
                                  size: 24,
                                )
                              : const Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  color: Colors.grey,
                                  size: 22,
                                ),
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            await ref
                                .read(selectedProviderIdProvider.notifier)
                                .setProvider(provider.id);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Switched to ${provider.name}'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: const Color(0xFF6342E8),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LanguageOption {
  final String code;
  final String englishName;
  final String nativeName;
  final String flag;

  const _LanguageOption({
    required this.code,
    required this.englishName,
    required this.nativeName,
    required this.flag,
  });
}

const List<_LanguageOption> _supportedLanguages = [
  _LanguageOption(
      code: 'en', englishName: 'English', nativeName: 'English', flag: '🇺🇸'),
  _LanguageOption(
      code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी', flag: '🇮🇳'),
  _LanguageOption(
      code: 'es', englishName: 'Spanish', nativeName: 'Español', flag: '🇪🇸'),
  _LanguageOption(
      code: 'fr', englishName: 'French', nativeName: 'Français', flag: '🇫🇷'),
  _LanguageOption(
      code: 'de', englishName: 'German', nativeName: 'Deutsch', flag: '🇩🇪'),
  _LanguageOption(
      code: 'it', englishName: 'Italian', nativeName: 'Italiano', flag: '🇮🇹'),
  _LanguageOption(
      code: 'pt',
      englishName: 'Portuguese',
      nativeName: 'Português',
      flag: '🇧🇷'),
  _LanguageOption(
      code: 'ru', englishName: 'Russian', nativeName: 'Русский', flag: '🇷🇺'),
  _LanguageOption(
      code: 'ar', englishName: 'Arabic', nativeName: 'العربية', flag: '🇸🇦'),
  _LanguageOption(
      code: 'ja', englishName: 'Japanese', nativeName: '日本語', flag: '🇯🇵'),
  _LanguageOption(
      code: 'ko', englishName: 'Korean', nativeName: '한국어', flag: '🇰🇷'),
  _LanguageOption(
      code: 'zh', englishName: 'Chinese', nativeName: '中文', flag: '🇨🇳'),
  _LanguageOption(
      code: 'bn', englishName: 'Bengali', nativeName: 'বাংলা', flag: '🇧🇩'),
  _LanguageOption(
      code: 'ur', englishName: 'Urdu', nativeName: 'اردو', flag: '🇵🇰'),
  _LanguageOption(
      code: 'id',
      englishName: 'Indonesian',
      nativeName: 'Bahasa Indonesia',
      flag: '🇮🇩'),
];

class _ProviderMeta {
  final String id;
  final String name;
  final String tag;
  final String description;
  final IconData icon;
  final Color color;

  const _ProviderMeta({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const List<_ProviderMeta> _allProvidersMeta = [
  _ProviderMeta(
    id: 'huggingface',
    name: 'HuggingFace',
    tag: 'Open-Source VTON',
    description: 'IDM-VTON & Kolors open-source models with your HuggingFace token',
    icon: Icons.hub_rounded,
    color: Color(0xFFF59E0B),
  ),
  _ProviderMeta(
    id: 'openai',
    name: 'OpenAI (ChatGPT)',
    tag: 'GPT-4o + DALL-E 3',
    description: 'ChatGPT Vision garment analysis with DALL-E 3 HD fashion rendering',
    icon: Icons.psychology_rounded,
    color: Color(0xFF10A37F),
  ),
  _ProviderMeta(
    id: 'fashn',
    name: 'Fashn.ai',
    tag: 'Top Fashion VTON',
    description: 'Dedicated enterprise Virtual Try-On API built for garments & models',
    icon: Icons.checkroom_rounded,
    color: Color(0xFF8B5CF6),
  ),
  _ProviderMeta(
    id: 'fal',
    name: 'Fal.ai',
    tag: 'Ultra-Fast GPU',
    description: 'Sub-10s ultra-fast Virtual Try-On inference in the cloud',
    icon: Icons.bolt_rounded,
    color: Color(0xFF10B981),
  ),
  _ProviderMeta(
    id: 'replicate',
    name: 'Replicate',
    tag: 'Popular',
    description: 'cuuupid/idm-vton, DaGAN, and diffusion apparel synthesis',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF3B82F6),
  ),
  _ProviderMeta(
    id: 'segmind',
    name: 'Segmind',
    tag: 'Diffusion',
    description: 'Segmind try-on-diffusion dedicated REST API with category control',
    icon: Icons.scatter_plot_rounded,
    color: Color(0xFFEC4899),
  ),
  _ProviderMeta(
    id: 'novita',
    name: 'Novita AI',
    tag: 'Cloud GPU',
    description: 'Serverless GPU cloud endpoint with native IDM-VTON support',
    icon: Icons.cloud_done_rounded,
    color: Color(0xFF06B6D4),
  ),
  _ProviderMeta(
    id: 'kling',
    name: 'Kling AI',
    tag: 'High Fidelity',
    description: 'High precision clothing drape & realistic body contour warping',
    icon: Icons.style_rounded,
    color: Color(0xFF6366F1),
  ),
  _ProviderMeta(
    id: 'custom',
    name: 'Custom Endpoint',
    tag: 'Self-Hosted',
    description: 'Connect Google Colab, RunPod, Modal, or local FastAPI server',
    icon: Icons.terminal_rounded,
    color: Color(0xFF64748B),
  ),
];

