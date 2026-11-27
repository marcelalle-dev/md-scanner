import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/router.dart';
import 'package:md_scanner/app/theme/app_theme.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';
import 'package:md_scanner/features/ocr/l10n/generated/ocr_localizations.dart';
import 'package:md_scanner/features/qr_scanner/l10n/generated/qr_localizations.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';

/// Delegates of every localized module, shared with the widget tests.
const List<LocalizationsDelegate<Object?>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  CoreLocalizations.delegate,
  OcrLocalizations.delegate,
  QrLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

class MdScannerApp extends ConsumerWidget {
  const MdScannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      title: 'MD SCANNER',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppSettings.supportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
    );
  }
}
