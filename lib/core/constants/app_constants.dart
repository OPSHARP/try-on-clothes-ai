/// App-wide constants and configuration values.
class AppConstants {
  AppConstants._();

  // ── App Info ──
  static const String appName = 'Try On Clothes AI';
  static const String appVersion = '1.0';
  static const String appDescription = 'AI-powered virtual fitting room';

  // ── Image Constraints ──
  static const double maxImageSizeMB = 10.0;
  static const int maxImageWidth = 2048;
  static const int maxImageHeight = 2048;
  static const List<String> supportedImageFormats = ['jpg', 'jpeg', 'png'];

  // ── Animation Durations ──
  static const Duration splashDuration = Duration(seconds: 3);
  static const Duration pageTransition = Duration(milliseconds: 300);
  static const Duration fadeAnimation = Duration(milliseconds: 500);
  static const Duration shimmerDuration = Duration(milliseconds: 1500);
  static const Duration generationTimeout = Duration(minutes: 2);

  // ── Storage Keys ──
  static const String keyOnboardingSeen = 'onboarding_seen';
  static const String keyApiSetupGuideSeen = 'api_setup_guide_seen';
  static const String keyThemeMode = 'theme_mode';
  static const String keyImageQuality = 'image_quality';
  static const String keyAutoSave = 'auto_save';
  static const String keyNotifications = 'notifications_enabled';
  static const String keyLanguage = 'language';
  static const String keySelectedProvider = 'selected_provider_id';
  static const String keyProviderApiKeyPrefix = 'provider_key_';
  static const String keyCustomApiEndpoint = 'custom_api_endpoint';
  static const String keyIsAdFree = 'is_ad_free';

  // ── AI Service ──
  static const Duration aiRequestTimeout = Duration(seconds: 120);

  // ── Subscription ──
  static const String subscriptionProductId = 'remove_ads';
  static const Set<String> subscriptionProductIds = {
    'remove_ads',
    'remove_ads_1_month',
    'monthly_remove_ads',
  };
  static const double subscriptionPriceUSD = 4.99;
  static const int subscriptionDurationMonths = 1;
  static const String subscriptionDurationLabel = '1 Month';
  static const double subscriptionMonthlyEquivalentUSD = 4.99;

  // ── Quality Options ──
  static const Map<String, String> qualityOptions = {
    'standard': 'Standard',
    'hd': 'HD',
    'ultra_hd': 'Ultra HD',
  };

  // ── Style Options ──
  static const Map<String, String> styleOptions = {
    'realistic': 'Realistic',
    'fashion': 'Fashion',
    'studio': 'Studio',
    'luxury': 'Luxury',
    'street': 'Street',
  };
}
