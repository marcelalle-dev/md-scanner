import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/storage/settings_store.dart';

/// App-wide preferences the root widget needs before the first frame.
///
/// Feature-specific preferences stay in their feature and go through
/// [SettingsStore] with their own keys.
class AppSettings extends Equatable {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.localeCode,
    this.onboardingCompleted = false,
  });

  factory AppSettings.fromMap(Map<String, String> values) {
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == values[keyThemeMode],
        orElse: () => ThemeMode.system,
      ),
      localeCode: supportedLocaleCodes.contains(values[keyLocale])
          ? values[keyLocale]
          : null,
      onboardingCompleted: values[keyOnboardingCompleted] == 'true',
    );
  }

  static const String keyThemeMode = 'app.theme_mode';
  static const String keyLocale = 'app.locale';
  static const String keyOnboardingCompleted = 'app.onboarding_completed';

  /// French first: it is the fallback when the device language is neither.
  static const List<String> supportedLocaleCodes = ['fr', 'en'];

  static const List<Locale> supportedLocales = [Locale('fr'), Locale('en')];

  final ThemeMode themeMode;

  /// `null` follows the device language.
  final String? localeCode;
  final bool onboardingCompleted;

  Locale? get locale => localeCode == null ? null : Locale(localeCode!);

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? Function()? localeCode,
    bool? onboardingCompleted,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    localeCode: localeCode != null ? localeCode() : this.localeCode,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
  );

  @override
  List<Object?> get props => [themeMode, localeCode, onboardingCompleted];
}

/// Settings read from SQLite by `bootstrap()` before `runApp`.
final initialAppSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialAppSettingsProvider);

  SettingsStore get _store => ref.read(settingsStoreProvider);

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _store.write(AppSettings.keyThemeMode, mode.name);
  }

  /// [code] null follows the device language.
  Future<void> setLocale(String? code) async {
    assert(code == null || AppSettings.supportedLocaleCodes.contains(code));
    state = state.copyWith(localeCode: () => code);
    if (code == null) {
      await _store.remove(AppSettings.keyLocale);
    } else {
      await _store.write(AppSettings.keyLocale, code);
    }
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingCompleted: true);
    await _store.writeBool(AppSettings.keyOnboardingCompleted, value: true);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );
