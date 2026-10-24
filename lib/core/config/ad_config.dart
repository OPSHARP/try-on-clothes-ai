/// AdMob configuration containing verified live ad unit IDs.
///
/// Configured for maximum eCPM earnings and strict Google AdMob / Play Console
/// Better Ads Standards compliance.
class AdConfig {
  AdConfig._();

  // ── Live Production AdMob IDs (Verified Live Accounts) ──
  static const String prodAppId =
      'ca-app-pub-6089131009548737~8408653143';
  static const String prodInterstitialAdUnitId =
      'ca-app-pub-6089131009548737/9354195460';
  static const String prodRewardedInterstitialAdUnitId =
      'ca-app-pub-6089131009548737/7095571470';

  /// Live AdMob App ID
  static String get appId => prodAppId;

  /// Live Interstitial Ad Unit ID
  static String get interstitialAdUnitId => prodInterstitialAdUnitId;

  /// Live Rewarded Interstitial Ad Unit ID
  static String get rewardedInterstitialAdUnitId =>
      prodRewardedInterstitialAdUnitId;

  /// Returns `false` (hide ads) if the user has an active ad-free subscription.
  /// Otherwise returns `true` (show ads).
  static bool shouldShowAds(bool isAdFree) {
    return !isAdFree;
  }
}
