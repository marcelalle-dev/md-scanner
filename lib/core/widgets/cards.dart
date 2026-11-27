import 'package:flutter/material.dart';
import 'package:md_scanner/app/theme/app_theme.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';

/// Small "Premium" marker placed on gated features.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({this.compact = false, super.key});

  /// Icon only, for tight layouts.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final premium = AppSemanticColors.of(context).premium;
    final label = CoreLocalizations.of(context).labelPremium;
    final icon = Icon(Icons.workspace_premium, size: 14, color: premium);
    if (compact) return Semantics(label: label, child: icon);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: premium.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Tappable tile presenting one tool (grid on Home and Tools screens).
class ToolCard extends StatelessWidget {
  const ToolCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.premium = false,
    this.accent,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool premium;

  /// Tint of the icon container; defaults to the secondary colour.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = accent ?? theme.colorScheme.secondary;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: AppRadius.control,
                    ),
                    child: Icon(icon, color: tint, size: 22),
                  ),
                  const Spacer(),
                  if (premium) const PremiumBadge(compact: true),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxs / 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Title of a screen section with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

enum InfoBannerTone { info, success, warning, danger }

/// Inline notice (offline, consent needed, limited feature…).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    required this.message,
    this.tone = InfoBannerTone.info,
    this.icon,
    this.action,
    super.key,
  });

  final String message;
  final InfoBannerTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final (Color color, IconData defaultIcon) = switch (tone) {
      InfoBannerTone.info => (theme.colorScheme.secondary, Icons.info_outline),
      InfoBannerTone.success => (semantic.success, Icons.check_circle_outline),
      InfoBannerTone.warning => (
        semantic.warning,
        Icons.warning_amber_outlined,
      ),
      InfoBannerTone.danger => (theme.colorScheme.error, Icons.error_outline),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: color, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          ?action,
        ],
      ),
    );
  }
}
