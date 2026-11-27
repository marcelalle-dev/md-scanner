import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';

/// Three-page introduction shown on first launch only.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  static const int _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(appSettingsProvider.notifier).completeOnboarding();
    if (mounted) context.go(AppRoutes.home);
  }

  void _next() {
    if (_index == _count - 1) {
      _finish();
    } else {
      _pages.nextPage(duration: AppDurations.normal, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final core = context.coreL10n;
    final scheme = Theme.of(context).colorScheme;
    final pages = [
      (Icons.document_scanner_outlined, l10n.onbTitle1, l10n.onbText1),
      (Icons.handyman_outlined, l10n.onbTitle2, l10n.onbText2),
      (Icons.shield_outlined, l10n.onbTitle3, l10n.onbText3),
    ];
    final last = _index == _count - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Visibility(
                visible: !last,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(core.actionSkip),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _count,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  final (icon, title, text) = pages[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: 60,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          text,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _count; i++)
                  AnimatedContainer(
                    duration: AppDurations.fast,
                    margin: const EdgeInsets.all(AppSpacing.xxs),
                    width: i == _index ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? scheme.secondary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last ? l10n.onbStart : core.actionNext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
