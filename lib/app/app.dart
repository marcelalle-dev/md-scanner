import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/router.dart';
import 'package:md_scanner/app/theme/app_theme.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';

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
      localizationsDelegates: const [
        AppLocalizations.delegate,
        CoreLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
    );
  }
}
