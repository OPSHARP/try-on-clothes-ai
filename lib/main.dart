import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'app.dart';
import 'core/providers/app_providers.dart';
import 'core/services/ad_service.dart';
import 'core/services/native_key_service.dart';

void main() async {
  // ── Step 1: Ensure Flutter binding is ready ──
  WidgetsFlutterBinding.ensureInitialized();

  // Strip all debugging and log output in release mode for security and performance
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // ── Step 2: Lock orientation to portrait ──
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Step 3: Initialize local storage ──
  final sharedPreferences = await SharedPreferences.getInstance();

  // ── Step 6: Launch the app UI ──
  // AdMob initialization is still deferred (post-first-frame) so the
  // initial UI paint is never blocked by AdMob's network calls.
  // But now the AdMob IDs it uses are already resolved from Remote Config.
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const _AppWithInit(),
    ),
  );
}

/// Wrapper that defers AdMob initialization so it doesn't block the
/// initial UI render. AdMob makes network calls that can delay
/// first-frame paint by 1-3 seconds.
class _AppWithInit extends ConsumerStatefulWidget {
  const _AppWithInit();

  @override
  ConsumerState<_AppWithInit> createState() => _AppWithInitState();
}

class _AppWithInitState extends ConsumerState<_AppWithInit> {
  @override
  void initState() {
    super.initState();

    // Post-frame background initialization:
    // 1. AdMob (deferred so initial UI paint isn't blocked)
    // 2. Native bundled API key loading via JNI MethodChannel
    // 3. Google Play In-App Flexible Update check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAdMob();
      _loadNativeKeys();
      _checkInAppUpdate();
    });
  }

  Future<void> _loadNativeKeys() async {
    try {
      final nativeHfKey = await NativeKeyService.getBundledApiKey('huggingface');
      if (nativeHfKey.isNotEmpty && mounted) {
        ref.read(nativeHuggingFaceKeyProvider.notifier).state = nativeHfKey;
        debugPrint('Native HuggingFace key loaded into provider');
      }
    } catch (e) {
      debugPrint('Error loading native key: $e');
    }
  }

  Future<void> _checkInAppUpdate() async {
    try {
      final updateService = ref.read(inAppUpdateServiceProvider);
      await updateService.checkForFlexibleUpdate();
    } catch (e) {
      debugPrint('In-app update check error: $e');
    }
  }

  Future<void> _initAdMob() async {
    await MobileAds.instance.initialize();
    debugPrint('AdMob initialized successfully (deferred)');

    // Signal AdMob readiness
    ref.read(admobInitializedProvider.notifier).state = true;

    // Preload live Interstitial and Rewarded Interstitial in the background
    final isAdFree = ref.read(isAdFreeProvider);
    if (!isAdFree) {
      AdService.instance.preloadAllAds();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const TryOnClothesApp();
  }
}
