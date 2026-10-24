import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/ai_provider_config.dart';

/// Wrapper around SharedPreferences for local key-value storage.
class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // ── Onboarding ──
  bool get hasSeenOnboarding =>
      _prefs.getBool(AppConstants.keyOnboardingSeen) ?? false;

  Future<void> setOnboardingSeen() =>
      _prefs.setBool(AppConstants.keyOnboardingSeen, true);

  // ── API Setup Guide ──
  bool get hasSeenApiSetupGuide =>
      _prefs.getBool(AppConstants.keyApiSetupGuideSeen) ?? false;

  Future<void> setApiSetupGuideSeen() =>
      _prefs.setBool(AppConstants.keyApiSetupGuideSeen, true);

  // ── Theme ──
  String get themeMode =>
      _prefs.getString(AppConstants.keyThemeMode) ?? 'system';

  Future<void> setThemeMode(String mode) =>
      _prefs.setString(AppConstants.keyThemeMode, mode);

  // ── Image Quality ──
  String get imageQuality =>
      _prefs.getString(AppConstants.keyImageQuality) ?? 'standard';

  Future<void> setImageQuality(String quality) =>
      _prefs.setString(AppConstants.keyImageQuality, quality);

  // ── Auto Save ──
  bool get autoSave => _prefs.getBool(AppConstants.keyAutoSave) ?? true;

  Future<void> setAutoSave(bool value) =>
      _prefs.setBool(AppConstants.keyAutoSave, value);

  // ── Notifications ──
  bool get notificationsEnabled =>
      _prefs.getBool(AppConstants.keyNotifications) ?? true;

  Future<void> setNotificationsEnabled(bool value) =>
      _prefs.setBool(AppConstants.keyNotifications, value);

  // ── AI Provider Selection ──
  /// The currently selected provider ID (e.g. 'huggingface', 'replicate', 'custom').
  String get selectedProviderId =>
      _prefs.getString(AppConstants.keySelectedProvider) ?? 'huggingface';

  Future<void> setSelectedProviderId(String id) =>
      _prefs.setString(AppConstants.keySelectedProvider, id);

  /// Get the API key for a given provider [id].
  String providerApiKey(String id) =>
      _prefs.getString('${AppConstants.keyProviderApiKeyPrefix}$id') ?? '';

  /// Save the API key for a given provider [id].
  Future<void> setProviderApiKey(String id, String key) =>
      _prefs.setString('${AppConstants.keyProviderApiKeyPrefix}$id', key);

  /// Clear the API key for a given provider [id].
  Future<void> clearProviderApiKey(String id) =>
      _prefs.remove('${AppConstants.keyProviderApiKeyPrefix}$id');

  // ── Custom API Endpoint ──
  String get customApiEndpoint =>
      _prefs.getString(AppConstants.keyCustomApiEndpoint) ?? '';

  Future<void> setCustomApiEndpoint(String url) =>
      _prefs.setString(AppConstants.keyCustomApiEndpoint, url);

  // ── Ads / Subscription ──
  bool get isAdFree => _prefs.getBool(AppConstants.keyIsAdFree) ?? false;

  Future<void> setIsAdFree(bool value) =>
      _prefs.setBool(AppConstants.keyIsAdFree, value);

  // ── Language ──
  String get language => _prefs.getString(AppConstants.keyLanguage) ?? 'en';

  Future<void> setLanguage(String lang) =>
      _prefs.setString(AppConstants.keyLanguage, lang);

  // ── Generic Storage ──
  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> removeKey(String key) => _prefs.remove(key);

  // ── Provider Configuration Helpers ──

  /// Convenience: returns the currently configured provider config
  /// based on the selected provider ID.
  AiProviderConfig? currentProviderConfig() {
    final id = selectedProviderId;
    return AiProviderConfig.fromId(id);
  }

  /// Returns a list of [AiProviderConfig] entries for which the user has
  /// saved a valid API key (and endpoint for custom).
  List<AiProviderConfig> getConfiguredProviders() {
    final providers = AiProviderConfig.builtIn;
    final configured = <AiProviderConfig>[];
    for (final provider in providers) {
      if (_hasApiKeyForProvider(provider)) {
        configured.add(provider);
      }
    }
    return configured;
  }

  /// Whether the user has configured at least one AI provider with a valid key.
  bool get hasAnyConfiguredProvider => getConfiguredProviders().isNotEmpty;

  /// Check if a specific provider has valid credentials saved.
  bool _hasApiKeyForProvider(AiProviderConfig provider) {
    if (provider.id == 'custom') {
      return providerApiKey('custom').isNotEmpty &&
          customApiEndpoint.isNotEmpty;
    }
    return providerApiKey(provider.id).isNotEmpty;
  }

  // ── Clear App Data ──
  /// Removes only app-specific preferences. Does NOT wipe all SharedPreferences
  /// so other apps/plugins using SharedPreferences are not affected.
  Future<void> clearAppData() async {
    final keysToRemove = [
      AppConstants.keyOnboardingSeen,
      AppConstants.keyThemeMode,
      AppConstants.keyImageQuality,
      AppConstants.keyAutoSave,
      AppConstants.keyNotifications,
      AppConstants.keyLanguage,
      AppConstants.keySelectedProvider,
      AppConstants.keyCustomApiEndpoint,
      AppConstants.keyIsAdFree,
      // API keys are stored with a prefix — iterate to remove all
    ];
    for (final key in keysToRemove) {
      await _prefs.remove(key);
    }
    // Remove all provider API keys (they use the prefix 'provider_key_')
    final allKeys = _prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith(AppConstants.keyProviderApiKeyPrefix)) {
        await _prefs.remove(key);
      }
    }
  }
}
