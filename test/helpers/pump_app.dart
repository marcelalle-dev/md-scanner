import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/app/theme/app_theme.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';

/// Pumps [child] inside the app's theme, localizations and a ProviderScope.
///
/// Pass the feature's own delegate in [delegates]
/// (`[OcrLocalizations.delegate]`); core and Material delegates are included.
/// Use [router] instead of [child] to test navigation with a GoRouter.
extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget child, {
    List<Override> overrides = const [],
    List<LocalizationsDelegate<Object?>> delegates = const [],
    Locale locale = const Locale('fr'),
    ThemeMode themeMode = ThemeMode.light,
    RouterConfig<Object>? router,
  }) async {
    final allDelegates = <LocalizationsDelegate<Object?>>[
      ...delegates,
      CoreLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];
    const supportedLocales = [Locale('fr'), Locale('en')];

    await pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: router != null
            ? MaterialApp.router(
                routerConfig: router,
                locale: locale,
                supportedLocales: supportedLocales,
                localizationsDelegates: allDelegates,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: themeMode,
              )
            : MaterialApp(
                home: child,
                locale: locale,
                supportedLocales: supportedLocales,
                localizationsDelegates: allDelegates,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: themeMode,
              ),
      ),
    );
    await pump();
  }
}
