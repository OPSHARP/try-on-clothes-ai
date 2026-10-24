import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/storage_service.dart';
import '../services/ai_service.dart';
import '../services/subscription_service.dart';
import '../services/history_service.dart';
import '../services/impl/huggingface_service.dart';
import '../services/impl/replicate_service.dart';
import '../services/impl/custom_api_service.dart';
import '../services/impl/fal_ai_service.dart';
import '../services/impl/segmind_service.dart';
import '../services/impl/fashn_service.dart';
import '../services/impl/novita_service.dart';
import '../services/impl/openai_service.dart';
import '../models/ai_provider_config.dart';
import '../services/in_app_update_service.dart';
import '../services/native_key_service.dart';
import '../services/ai_image_pipeline_service.dart';

import '../../data/models/generation_model.dart';

/// Provider for SharedPreferences instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

/// Provider for StorageService (local persistence).
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(sharedPreferencesProvider));
});

/// Theme mode provider: 'light', 'dark', or 'system'.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, String>((
  ref,
) {
  final storage = ref.watch(storageServiceProvider);
  return ThemeModeNotifier(storage);
});

class ThemeModeNotifier extends StateNotifier<String> {
  final StorageService _storage;

  ThemeModeNotifier(this._storage) : super(_storage.themeMode);

  Future<void> setTheme(String mode) async {
    state = mode;
    await _storage.setThemeMode(mode);
  }

  void toggle() {
    if (state == 'dark') {
      setTheme('light');
    } else {
      setTheme('dark');
    }
  }
}

/// Language provider for app localization: 'en', 'hi', 'es', etc.
final languageProvider = StateNotifierProvider<LanguageNotifier, String>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return LanguageNotifier(storage);
});

class LanguageNotifier extends StateNotifier<String> {
  final StorageService _storage;

  LanguageNotifier(this._storage) : super(_storage.language);

  Future<void> setLanguage(String code) async {
    state = code;
    await _storage.setLanguage(code);
  }
}

/// Onboarding seen state - watches storage service to detect changes.
final hasSeenOnboardingProvider = Provider<bool>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.hasSeenOnboarding;
});

/// API Setup guide seen state.
final hasSeenApiSetupGuideProvider = Provider<bool>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.hasSeenApiSetupGuide;
});

/// ── AI Provider Configuration ──

/// Provider that exposes the currently selected provider's config.
final selectedProviderConfigProvider = Provider<AiProviderConfig?>((ref) {
  final providerId = ref.watch(selectedProviderIdProvider);
  return AiProviderConfig.fromId(providerId);
});

/// ── AI Service Provider (Factory) ──

/// Returns the appropriate [AiService] implementation based on the
/// user's selected provider and their stored API key/endpoint.
///
/// Returns `null` if the selected provider's API key is not configured.
final aiServiceProvider = Provider<AiService?>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final providerId = ref.watch(selectedProviderIdProvider);
  final userKey = storage.providerApiKey(providerId);

  // HuggingFace multi-tier key resolution:
  // Tier 1: User custom key from Settings (BYOK)
  // Tier 2: Native JNI obfuscated C++ key loaded at boot
  // Tier 3: HuggingFaceService default key
  final apiKey = userKey.isNotEmpty
      ? userKey
      : (providerId == 'huggingface'
          ? (ref.watch(nativeHuggingFaceKeyProvider).isNotEmpty
              ? ref.watch(nativeHuggingFaceKeyProvider)
              : HuggingFaceService.defaultApiKey)
          : '');

  // Other cloud providers (OpenAI, Replicate, Fal, etc.) require the user's API key.
  if (apiKey.isEmpty && providerId != 'huggingface') {
    return null;
  }

  switch (providerId) {
    case 'huggingface':
      return HuggingFaceService(apiKey: apiKey);
    case 'openai':
      return OpenAiService(apiKey: apiKey);
    case 'fashn':
      return FashnService(apiKey: apiKey);
    case 'novita':
      return NovitaService(apiKey: apiKey);
    case 'kling':
      return NovitaService(apiKey: apiKey); // Novita/Kling compatible VTON payload
    case 'replicate':
      return ReplicateService(apiKey: apiKey);
    case 'fal':
      return FalAiService(apiKey: apiKey);
    case 'segmind':
      return SegmindService(apiKey: apiKey);
    case 'custom':
      final endpoint = storage.customApiEndpoint;
      return CustomApiService(apiKey: apiKey, endpointUrl: endpoint);
    default:
      return null;
  }
});

/// Provider for the AI Multi-Skill Image Generation & Enhancement Pipeline.
final aiImagePipelineServiceProvider = Provider<AiImagePipelineService?>((ref) {
  final aiService = ref.watch(aiServiceProvider);
  if (aiService == null) return null;
  return AiImagePipelineService(aiService);
});

/// Holds native JNI bundled HuggingFace key loaded on startup (now empty/decoupled)
final nativeHuggingFaceKeyProvider = StateProvider<String>((ref) => '');

/// Highest hardware display refresh rate supported by the user's phone (e.g. 120, 90, 60)
final maxDisplayRefreshRateProvider = FutureProvider<int>((ref) async {
  final fps = await NativeKeyService.getMaxFps();
  return fps.round();
});

/// StateNotifier that manages the selected provider ID and persists changes.
class SelectedProviderNotifier extends StateNotifier<String> {
  final StorageService _storage;

  SelectedProviderNotifier(this._storage) : super(_storage.selectedProviderId);

  Future<void> setProvider(String id) async {
    state = id;
    await _storage.setSelectedProviderId(id);
  }
}

/// Provider that rebuilds whenever the selected provider changes.
/// Used by widgets that need to react to provider switches.
final selectedProviderIdProvider =
    StateNotifierProvider<SelectedProviderNotifier, String>((ref) {
      final storage = ref.watch(storageServiceProvider);
      return SelectedProviderNotifier(storage);
    });

/// ── Subscription Service ──

class IsAdFreeNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  IsAdFreeNotifier(this._storage) : super(_storage.isAdFree);

  Future<void> setIsAdFree(bool value) async {
    state = value;
    await _storage.setIsAdFree(value);
  }
}

/// Whether the user has an active ad-free subscription (reactive state notifier).
final isAdFreeProvider = StateNotifierProvider<IsAdFreeNotifier, bool>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return IsAdFreeNotifier(storage);
});

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final purchase = InAppPurchase.instance;
  final service = SubscriptionService(
    purchase: purchase,
    storage: storage,
    onAdFreeChanged: (isAdFree) {
      ref.read(isAdFreeProvider.notifier).setIsAdFree(isAdFree);
    },
  );
  ref.onDispose(() => service.dispose());
  // Initialize asynchronously
  service.initialize();
  return service;
});

/// ── In-App Update Service ──
final inAppUpdateServiceProvider = Provider<InAppUpdateService>((ref) {
  return InAppUpdateService();
});

/// Tracks whether AdMob has finished initializing.
/// Used by [AdBanner] to delay loading until AdMob is ready.
final admobInitializedProvider = StateProvider<bool>((ref) => false);

/// ── History Service ──

/// Provider for [HistoryService] (generation history persistence).
final historyServiceProvider = Provider<HistoryService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return HistoryService(storage: storage);
});

/// Provider that exposes the list of past generations as a [List<GenerationModel>].
/// Automatically rebuilds when invalidated (call `ref.invalidate(historyListProvider)`
/// after adding/updating history entries).
final historyListProvider = Provider<List<GenerationModel>>((ref) {
  final historyService = ref.watch(historyServiceProvider);
  return historyService.getHistory();
});

/// ── API Key Status ──

/// Provider that checks whether the user has configured at least one API key
/// across all providers. Returns `true` as soon as any provider (including
/// HuggingFace) has a valid key+endpoint configured.
///
/// This powers the API key banner on the home screen — once a key is saved
/// for *any* provider the banner disappears immediately.
final hasApiKeyForProviderProvider = Provider<bool>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final providerId = ref.watch(selectedProviderIdProvider);
  if (providerId == 'huggingface') {
    return true; // 100% Free - operates via public Gradio queue without requiring any API key
  }
  return storage.hasAnyConfiguredProvider;
});

/// Provider that returns a list of [AiProviderConfig] entries for which the
/// user has saved a valid API key (and endpoint for custom).
/// Used by the Try On screen's provider selector dropdown.
final configuredProvidersProvider = Provider<List<AiProviderConfig>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.getConfiguredProviders();
});
