import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/ad_config.dart';

/// Production AdMob Service handling Live Interstitial and Rewarded Interstitial Ads.
///
/// Designed to maximize eCPM revenue while strictly complying with Google AdMob
/// Policies and Google Play Console Better Ads Standards (no disruptive popups,
/// safe frequency capping, preloaded cache, natural transition triggers).
class AdService {
  static final AdService instance = AdService._internal();
  factory AdService() => instance;
  AdService._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;
  Completer<bool>? _interstitialCompleter;

  RewardedInterstitialAd? _rewardedInterstitialAd;
  bool _isRewardedInterstitialLoading = false;
  Completer<bool>? _rewardedCompleter;

  // ── Frequency Capping & Policy Compliance ──
  // Google Play Better Ads Standards recommend avoiding rapid back-to-back
  // full screen ads. We maintain a 45-second cooldown between full-screen ads.
  static DateTime? _lastFullScreenAdShownTime;
  static const Duration _minIntervalBetweenAds = Duration(seconds: 45);

  // ── Result / Generation Counter for "Every 2nd Result" Ad Trigger ──
  static int _generationResultCount = 0;

  /// Current number of generation results completed in this app session.
  static int get generationResultCount => _generationResultCount;

  /// Returns true if the UPCOMING generation is the 2nd result (i.e. generation #2, #4, #6...).
  /// This allows triggering the ad during generation time while background synthesis runs.
  static bool shouldTriggerForNextGeneration() {
    return (_generationResultCount + 1) % 2 == 0;
  }

  /// Records that a generation has completed successfully.
  static void recordGenerationCompleted() {
    _generationResultCount++;
    if (kDebugMode) {
      debugPrint('AdService: Generation #$_generationResultCount completed.');
    }
  }

  /// Increments the generation count and returns true if this result should trigger an Interstitial Ad.
  /// Strictly triggers on every 2nd result (i.e. result 2, 4, 6, 8...).
  static bool onGenerationResultCompleted() {
    _generationResultCount++;
    final shouldTrigger = (_generationResultCount % 2 == 0);
    if (kDebugMode) {
      debugPrint('AdService: Generation result #$_generationResultCount completed. Interstitial trigger: $shouldTrigger');
    }
    return shouldTrigger;
  }

  /// Resets the generation counter (used for testing or session reset).
  static void resetGenerationCounter() {
    _generationResultCount = 0;
  }


  /// Returns true if cooldown has elapsed and a new full-screen ad can be safely shown.
  static bool get canShowFullScreenAd {
    if (_lastFullScreenAdShownTime == null) return true;
    return DateTime.now().difference(_lastFullScreenAdShownTime!) >=
        _minIntervalBetweenAds;
  }

  /// Whether an interstitial ad is preloaded and ready to show.
  bool get isInterstitialReady => _interstitialAd != null;

  /// Whether a rewarded interstitial ad is preloaded and ready to show.
  bool get isRewardedInterstitialReady => _rewardedInterstitialAd != null;

  /// Preloads both live ad formats in background for zero-latency presentation.
  void preloadAllAds() {
    loadInterstitial();
    loadRewardedInterstitial();
  }

  // ── 1. LIVE INTERSTITIAL AD ──

  /// Preloads the user's live Interstitial ad unit.
  Future<bool> loadInterstitial() async {
    if (_interstitialAd != null) return true;
    if (_isInterstitialLoading && _interstitialCompleter != null) {
      return _interstitialCompleter!.future;
    }

    _isInterstitialLoading = true;
    _interstitialCompleter = Completer<bool>();

    try {
      await InterstitialAd.load(
        adUnitId: AdConfig.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAd = ad;
            _isInterstitialLoading = false;
            if (_interstitialCompleter != null && !_interstitialCompleter!.isCompleted) {
              _interstitialCompleter!.complete(true);
            }
            if (kDebugMode) {
              debugPrint('Live Interstitial ad loaded successfully');
            }
          },
          onAdFailedToLoad: (error) {
            _interstitialAd = null;
            _isInterstitialLoading = false;
            if (_interstitialCompleter != null && !_interstitialCompleter!.isCompleted) {
              _interstitialCompleter!.complete(false);
            }
            if (kDebugMode) {
              debugPrint('Live Interstitial ad failed to load: $error');
            }
          },
        ),
      );
    } catch (e) {
      _interstitialAd = null;
      _isInterstitialLoading = false;
      if (_interstitialCompleter != null && !_interstitialCompleter!.isCompleted) {
        _interstitialCompleter!.complete(false);
      }
      if (kDebugMode) {
        debugPrint('Live Interstitial ad load exception: $e');
      }
    }

    return _interstitialCompleter!.future;
  }

  /// Shows the live interstitial ad at natural transition points.
  ///
  /// Returns `true` if the ad was successfully presented.
  Future<bool> showInterstitial({bool ignoreCooldown = false}) async {
    var ad = _interstitialAd;
    if (ad == null) {
      // If not yet ready, give it an opportunity to load
      await loadInterstitial();
      ad = _interstitialAd;
      if (ad == null) return false;
    }

    if (!ignoreCooldown && !canShowFullScreenAd) {
      if (kDebugMode) {
        debugPrint('Interstitial ad skipped due to frequency cap cooldown');
      }
      return false;
    }

    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _lastFullScreenAdShownTime = DateTime.now();
        if (kDebugMode) debugPrint('Live Interstitial ad presented');
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        completer.complete(true);
        if (kDebugMode) debugPrint('Live Interstitial ad dismissed');
        // Preload next interstitial immediately
        loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        completer.complete(false);
        if (kDebugMode) {
          debugPrint('Live Interstitial failed to show: $error');
        }
        // Preload next interstitial immediately
        loadInterstitial();
      },
    );

    ad.show();
    return completer.future;
  }

  // ── 2. LIVE REWARDED INTERSTITIAL AD (HIGHEST eCPM FORMAT) ──

  /// Preloads the user's live Rewarded Interstitial ad unit.
  Future<bool> loadRewardedInterstitial() async {
    if (_rewardedInterstitialAd != null) return true;
    if (_isRewardedInterstitialLoading && _rewardedCompleter != null) {
      return _rewardedCompleter!.future;
    }

    _isRewardedInterstitialLoading = true;
    _rewardedCompleter = Completer<bool>();

    try {
      await RewardedInterstitialAd.load(
        adUnitId: AdConfig.rewardedInterstitialAdUnitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback:
            RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedInterstitialAd = ad;
            _isRewardedInterstitialLoading = false;
            if (_rewardedCompleter != null && !_rewardedCompleter!.isCompleted) {
              _rewardedCompleter!.complete(true);
            }
            if (kDebugMode) {
              debugPrint('Live Rewarded Interstitial ad loaded successfully');
            }
          },
          onAdFailedToLoad: (error) {
            _rewardedInterstitialAd = null;
            _isRewardedInterstitialLoading = false;
            if (_rewardedCompleter != null && !_rewardedCompleter!.isCompleted) {
              _rewardedCompleter!.complete(false);
            }
            if (kDebugMode) {
              debugPrint('Live Rewarded Interstitial failed to load: $error');
            }
          },
        ),
      );
    } catch (e) {
      _rewardedInterstitialAd = null;
      _isRewardedInterstitialLoading = false;
      if (_rewardedCompleter != null && !_rewardedCompleter!.isCompleted) {
        _rewardedCompleter!.complete(false);
      }
      if (kDebugMode) {
        debugPrint('Live Rewarded Interstitial load exception: $e');
      }
    }

    return _rewardedCompleter!.future;
  }

  /// Shows the live Rewarded Interstitial ad.
  ///
  /// The AdMob SDK displays a compliant introductory countdown giving the
  /// user the opportunity to skip or watch.
  ///
  /// [onUserEarnedReward] is triggered when user completes the rewarded duration.
  /// Returns `true` if the ad was shown.
  Future<bool> showRewardedInterstitial({
    void Function(RewardItem reward)? onUserEarnedReward,
    VoidCallback? onDismissed,
  }) async {
    final ad = _rewardedInterstitialAd;
    if (ad == null) {
      // Trigger preload for future attempts
      loadRewardedInterstitial();
      return false;
    }

    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _lastFullScreenAdShownTime = DateTime.now();
        if (kDebugMode) debugPrint('Live Rewarded Interstitial ad presented');
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedInterstitialAd = null;
        onDismissed?.call();
        completer.complete(true);
        if (kDebugMode) debugPrint('Live Rewarded Interstitial ad dismissed');
        // Preload next ad immediately
        loadRewardedInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedInterstitialAd = null;
        onDismissed?.call();
        completer.complete(false);
        if (kDebugMode) {
          debugPrint('Live Rewarded Interstitial failed to show: $error');
        }
        // Preload next ad immediately
        loadRewardedInterstitial();
      },
    );

    ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        if (kDebugMode) {
          debugPrint(
            'Live Rewarded Interstitial reward earned: ${reward.amount} ${reward.type}',
          );
        }
        onUserEarnedReward?.call(reward);
      },
    );

    return completer.future;
  }

  // ── Cleanup ──

  /// Disposes all ads in cache.
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _interstitialCompleter = null;
    _isInterstitialLoading = false;

    _rewardedInterstitialAd?.dispose();
    _rewardedInterstitialAd = null;
    _rewardedCompleter = null;
    _isRewardedInterstitialLoading = false;
  }
}

/// Zero-footprint placeholder widget keeping layout clean.
class AdBanner extends StatelessWidget {
  const AdBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
