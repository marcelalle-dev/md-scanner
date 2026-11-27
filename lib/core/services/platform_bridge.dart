import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State of the camera permission as reported by Android.
enum CameraPermissionStatus {
  granted,

  /// Not granted. The system dialog may still be shown by the camera plugins.
  denied,

  /// Denied once: Android expects an explanation before asking again.
  rationale,

  /// The host platform could not answer (tests, unsupported platform).
  unknown,
}

/// Thin bridge to the three native capabilities implemented in
/// `MainActivity.kt` that do not justify a dedicated plugin.
///
/// Every call degrades gracefully when the native side is absent (unit and
/// widget tests): nothing throws.
class PlatformBridge {
  const PlatformBridge([this._channel = const MethodChannel(channelName)]);

  static const String channelName = 'dev.marcelalle.mdscanner/platform';

  final MethodChannel _channel;

  /// Blocks screenshots and hides the app preview in the recents screen
  /// while [secure] is true. Used by the vault and the PIN screens.
  Future<void> setSecureWindow({required bool secure}) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // No native side (tests): nothing to protect.
    } on PlatformException {
      // The window flag is best effort; failing to set it must not break the UI.
    }
  }

  Future<CameraPermissionStatus> cameraPermissionStatus() async {
    try {
      final status = await _channel.invokeMethod<String>(
        'cameraPermissionStatus',
      );
      return switch (status) {
        'granted' => CameraPermissionStatus.granted,
        'denied' => CameraPermissionStatus.denied,
        'rationale' => CameraPermissionStatus.rationale,
        _ => CameraPermissionStatus.unknown,
      };
    } on MissingPluginException {
      return CameraPermissionStatus.unknown;
    } on PlatformException {
      return CameraPermissionStatus.unknown;
    }
  }

  /// Opens the system settings page of the app so the user can change a
  /// permission. Returns false when the page could not be opened.
  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

final platformBridgeProvider = Provider<PlatformBridge>(
  (ref) => const PlatformBridge(),
);
