import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/configuration/app_config.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/progress.dart';
import 'package:md_scanner/features/ads/data/ads_service.dart';
import 'package:md_scanner/features/premium/l10n/generated/premium_localizations.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:md_scanner/shared/services/backup_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// Bytes used by the app storage, recomputed when the library changes.
final _storageBytesProvider = FutureProvider.autoDispose<int>((ref) async {
  final repository = ref.watch(documentRepositoryProvider);
  final subscription = repository.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return ref.watch(fileStorageProvider).usedBytes();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      context.showMessage(context.coreL10n.errorUnexpected);
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final storage = ref.read(fileStorageProvider);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final destination = p.join(
      storage.directoryOf(StorageArea.exports).path,
      'md-scanner-backup-$stamp.zip',
    );
    final result = await runWithProgress(
      context,
      message: l10n.backupExporting,
      task: (progress) => ref
          .read(backupServiceProvider)
          .exportBackup(
            destinationPath: destination,
            onProgress: progress.report,
          ),
    );
    if (!context.mounted) return;
    switch (result) {
      case Success():
        await SharePlus.instance.share(
          ShareParams(files: [XFile(destination, mimeType: 'application/zip')]),
        );
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null || !context.mounted) return;
    final result = await runWithProgress(
      context,
      message: l10n.backupRestoring,
      task: (progress) => ref
          .read(backupServiceProvider)
          .restoreBackup(
            archivePath: path,
            mode: RestoreMode.merge,
            onProgress: progress.report,
          ),
    );
    if (!context.mounted) return;
    switch (result) {
      case Success():
        context.showMessage(l10n.backupRestored);
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final core = context.coreL10n;
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final version = ref.watch(_packageInfoProvider).value;
    final usedBytes = ref.watch(_storageBytesProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _PremiumTile(),
          _Section(l10n.profileAppearance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_outlined),
                  label: Text(l10n.themeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: Text(l10n.themeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  label: Text(l10n.themeDark),
                ),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  controller.setThemeMode(value.first),
            ),
          ),
          _Section(l10n.profileLanguage),
          for (final (code, label) in [
            (null, l10n.languageSystem),
            ('fr', 'Français'),
            ('en', 'English'),
          ])
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(label),
              trailing: settings.localeCode == code
                  ? const Icon(Icons.check)
                  : null,
              selected: settings.localeCode == code,
              onTap: () => controller.setLocale(code),
            ),
          _Section(l10n.profileBackup),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(l10n.profileStorage),
            trailing: Text(
              usedBytes == null ? '…' : formatFileSize(core, usedBytes),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(l10n.backupExport),
            subtitle: Text(l10n.backupExportHint),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: Text(l10n.backupRestore),
            subtitle: Text(l10n.backupRestoreHint),
            onTap: () => _restoreBackup(context, ref),
          ),
          _Section(l10n.profileAbout),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.profilePrivacy),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, AppConfig.privacyPolicyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.profileHelp),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, AppConfig.supportUrl),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(l10n.profileLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: core.appName,
              applicationVersion: version?.version,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(
              version == null
                  ? core.appName
                  : l10n.profileVersion(
                      '${version.version} (${version.buildNumber})',
                    ),
            ),
            subtitle: Text(l10n.profilePublisher),
          ),
        ],
      ),
    );
  }
}

class _PremiumTile extends ConsumerWidget {
  const _PremiumTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = PremiumLocalizations.of(context);
    final premium = ref.watch(isPremiumProvider);
    final ads = ref.watch(adsServiceProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(premium ? l10n.premiumEntryActive : l10n.premiumEntry),
          subtitle: premium ? null : Text(l10n.premiumEntryHint),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.premium),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: ads.privacyOptionsRequired,
          builder: (context, required, _) => required
              ? ListTile(
                  leading: const Icon(Icons.ads_click_outlined),
                  title: Text(l10n.adsPrivacy),
                  onTap: ads.showPrivacyOptions,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SectionHeader(title: title),
  );
}
