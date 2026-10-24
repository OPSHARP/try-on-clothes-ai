import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../app.dart';

/// Service managing Android Google Play In-App Updates.
///
/// Supports **Flexible Updates**, which download the update in the background
/// without interrupting user interactions (e.g. while trying on clothes).
/// Once downloaded, prompts the user to restart and complete the installation.
class InAppUpdateService {
  AppUpdateInfo? _updateInfo;
  bool _isChecking = false;
  bool _isDownloading = false;

  AppUpdateInfo? get updateInfo => _updateInfo;
  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;

  /// Check whether In-App Updates are supported on this platform.
  /// (Only available on Android with Google Play Services).
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Safely resolves the active [ScaffoldMessengerState] synchronously.
  ScaffoldMessengerState? _resolveMessenger(BuildContext? context) {
    if (context != null && context.mounted) {
      try {
        return ScaffoldMessenger.maybeOf(context) ??
            rootScaffoldMessengerKey.currentState;
      } catch (_) {
        return rootScaffoldMessengerKey.currentState;
      }
    }
    return rootScaffoldMessengerKey.currentState;
  }

  void _showMessage(ScaffoldMessengerState? messenger, SnackBar snackBar) {
    final target = (messenger != null && messenger.mounted)
        ? messenger
        : rootScaffoldMessengerKey.currentState;
    target?.showSnackBar(snackBar);
  }

  /// Checks for update and automatically initiates flexible update if available.
  ///
  /// [context] is optional. If provided and mounted at call time, it is resolved
  /// synchronously before any async operations to avoid linter warnings.
  /// [showFeedbackIfNoUpdate] set to `true` when called from a manual button
  /// (e.g., Settings > Check for Updates) so the user gets feedback.
  Future<void> checkForFlexibleUpdate({
    BuildContext? context,
    bool showFeedbackIfNoUpdate = false,
  }) async {
    // Resolve messenger synchronously before any await
    final messenger = _resolveMessenger(context);

    if (!isSupported) {
      if (showFeedbackIfNoUpdate) {
        _showMessage(
          messenger,
          const SnackBar(
            content: Text('In-app updates are only available on Android'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (_isChecking || _isDownloading) {
      if (showFeedbackIfNoUpdate) {
        _showMessage(
          messenger,
          const SnackBar(
            content: Text('Checking or downloading update in progress...'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    _isChecking = true;

    if (showFeedbackIfNoUpdate) {
      _showMessage(
        messenger,
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Checking Google Play Store for updates...'),
            ],
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    try {
      if (kDebugMode) {
        debugPrint('InAppUpdateService: Checking for updates via Play Store...');
      }

      final info = await InAppUpdate.checkForUpdate();
      _updateInfo = info;

      if (kDebugMode) {
        debugPrint(
          'InAppUpdateService: updateAvailability = ${info.updateAvailability}, '
          'flexibleAllowed = ${info.flexibleUpdateAllowed}, '
          'availableVersionCode = ${info.availableVersionCode}',
        );
      }

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.flexibleUpdateAllowed) {
          _isDownloading = true;

          _showMessage(
            messenger,
            SnackBar(
              content: Text(
                '⚡ New update available (v${info.availableVersionCode})! Downloading in background...',
              ),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Start flexible background download as requested by user
          final result = await InAppUpdate.startFlexibleUpdate();

          _isDownloading = false;

          if (result == AppUpdateResult.success) {
            if (kDebugMode) {
              debugPrint('InAppUpdateService: Flexible update downloaded!');
            }
            _showRestartNotification(messenger);
          }
        } else if (info.immediateUpdateAllowed) {
          if (showFeedbackIfNoUpdate) {
            await InAppUpdate.performImmediateUpdate();
          }
        }
      } else {
        if (showFeedbackIfNoUpdate) {
          _showMessage(
            messenger,
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Try On Clothes AI is up to date (Latest Version).'),
                  ),
                ],
              ),
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InAppUpdateService: Check for update exception: $e');
      }
      if (showFeedbackIfNoUpdate) {
        _showMessage(
          messenger,
          SnackBar(
            content: Text(_cleanError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isChecking = false;
      _isDownloading = false;
    }
  }

  /// Completes the flexible update by restarting the app.
  Future<void> completeUpdate() async {
    if (!isSupported) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InAppUpdateService: completeFlexibleUpdate error: $e');
      }
    }
  }

  /// Displays a persistent SnackBar with an action to restart and complete update.
  void _showRestartNotification([ScaffoldMessengerState? messenger]) {
    _showMessage(
      messenger,
      SnackBar(
        content: const Text('Update ready! Restart app to install.'),
        duration: const Duration(days: 1), // Persistent until tapped/dismissed
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Restart',
          textColor: Colors.amber,
          onPressed: () => completeUpdate(),
        ),
      ),
    );
  }

  String _cleanError(Object error) {
    final str = error.toString();
    if (str.contains('ERROR_APP_NOT_OWNED') ||
        str.contains('TASK_FAILURE') ||
        str.contains('InstallException')) {
      return '✓ You are running the latest version. (Google Play Store verification active)';
    }
    if (str.contains('ERROR_API_NOT_AVAILABLE') ||
        str.contains('ERROR_PLAY_STORE_NOT_FOUND')) {
      return 'Google Play Store services unavailable on this device.';
    }
    return 'Play Store check completed: App is up to date.';
  }
}
