import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/platform_bridge.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/progress.dart';
import 'package:md_scanner/features/document_scanner/domain/document_capture.dart';
import 'package:md_scanner/features/id_scanner/domain/id_parser.dart';
import 'package:md_scanner/features/id_scanner/domain/id_scan_service.dart';
import 'package:md_scanner/features/id_scanner/l10n/generated/id_scanner_localizations.dart';
import 'package:uuid/uuid.dart';

/// Front and back capture of an identity document, automatic reading of its
/// information, and export as a PDF.
class IdScannerScreen extends ConsumerStatefulWidget {
  const IdScannerScreen({super.key});

  @override
  ConsumerState<IdScannerScreen> createState() => _IdScannerScreenState();
}

class _IdScannerScreenState extends ConsumerState<IdScannerScreen> {
  final String _sessionId = const Uuid().v4();
  late final IdScanService _service = ref.read(idScanServiceProvider);
  late final PlatformBridge _bridge = ref.read(platformBridgeProvider);
  IdSide? _front;
  IdSide? _back;
  IdFields? _fields;

  List<IdSide> get _sides => [?_front, ?_back];

  @override
  void initState() {
    super.initState();
    // Identity documents must not end up in screenshots or the recents list.
    _bridge.setSecureWindow(secure: true);
  }

  @override
  void dispose() {
    _bridge.setSecureWindow(secure: false);
    _service.discard(_sessionId);
    super.dispose();
  }

  Future<void> _capture({required bool front, required bool camera}) async {
    final capture = ref.read(documentCaptureProvider);
    final picked = camera
        ? await capture.scanWithCamera(pageLimit: 1)
        : await capture.pickFromGallery();
    if (!mounted) return;
    final Result<IdSide> result = await picked.andThen(
      (paths) => _service.addSide(_sessionId, paths.first, imported: !camera),
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() {
          front ? _front = value : _back = value;
          _fields = null;
        });
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  Future<void> _analyze() async {
    final l10n = IdScannerLocalizations.of(context);
    final result = await runWithProgress(
      context,
      message: l10n.idAnalyzing,
      task: (_) => _service.analyze(_sides),
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() => _fields = value);
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  Future<void> _save() async {
    final l10n = IdScannerLocalizations.of(context);
    final fields = _fields;
    final name = [
      l10n.idDefaultName,
      if (fields?.surname != null) fields!.surname!,
    ].join(' ');
    final result = await runWithProgress(
      context,
      message: context.coreL10n.labelProcessing,
      task: (_) => _service.savePdf(name, _sides),
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        context.showMessage(l10n.idSaved);
        context.pushReplacement(AppRoutes.documentDetails(value.id));
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = IdScannerLocalizations.of(context);
    final fields = _fields;
    final hasSide = _sides.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.idTitle)),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          InfoBanner(message: l10n.idPrivacy, icon: Icons.privacy_tip_outlined),
          const SizedBox(height: AppSpacing.md),
          _SideCard(
            title: l10n.idFront,
            side: _front,
            onCamera: () => _capture(front: true, camera: true),
            onGallery: () => _capture(front: true, camera: false),
            onRemove: () => setState(() {
              _front = null;
              _fields = null;
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SideCard(
            title: l10n.idBack,
            side: _back,
            onCamera: () => _capture(front: false, camera: true),
            onGallery: () => _capture(front: false, camera: false),
            onRemove: () => setState(() {
              _back = null;
              _fields = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: hasSide ? _analyze : null,
            icon: const Icon(Icons.manage_search),
            label: Text(l10n.idAnalyze),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: hasSide ? _save : null,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(l10n.idSavePdf),
          ),
          if (fields != null) ...[
            SectionHeader(title: l10n.idFields),
            if (fields.isEmpty)
              Text(l10n.idNoFields)
            else ...[
              if (fields.hasMrz)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: InfoBanner(
                    tone: fields.mrzChecksValid!
                        ? InfoBannerTone.success
                        : InfoBannerTone.warning,
                    message: fields.mrzChecksValid!
                        ? l10n.idMrzValid
                        : l10n.idMrzInvalid,
                  ),
                ),
              for (final (label, value) in [
                (l10n.idSurname, fields.surname),
                (l10n.idGivenNames, fields.givenNames),
                (l10n.idNumber, fields.documentNumber),
                (l10n.idBirth, fields.birthDate),
                (l10n.idExpiry, fields.expiryDate),
                (l10n.idNationality, fields.nationality),
                (l10n.idSex, fields.sex),
                (
                  l10n.idDates,
                  fields.otherDates.isEmpty
                      ? null
                      : fields.otherDates.join(' · '),
                ),
                (
                  l10n.idNumbers,
                  fields.otherNumbers.isEmpty
                      ? null
                      : fields.otherNumbers.join(' · '),
                ),
              ])
                if (value != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: SelectableText(value),
                  ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.idDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.title,
    required this.side,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final String title;
  final IdSide? side;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = IdScannerLocalizations.of(context);
    final side = this.side;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            if (side != null)
              ClipRRect(
                borderRadius: AppRadius.control,
                child: Image.file(
                  File(side.path),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  cacheHeight: 480,
                ),
              ),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                TextButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(l10n.idCapture),
                ),
                TextButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(l10n.idImport),
                ),
                if (side != null)
                  TextButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.idRemove),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
