import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/progress.dart';
import 'package:md_scanner/features/ads/data/ads_service.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool_runner.dart';
import 'package:md_scanner/features/pdf_tools/presentation/signature_pad.dart';
import 'package:path/path.dart' as p;

/// One screen drives every PDF tool: choose the input file(s), set the few
/// parameters the tool needs, run, and get the result in the library.
class PdfToolScreen extends ConsumerStatefulWidget {
  const PdfToolScreen({required this.tool, super.key});

  final PdfTool tool;

  @override
  ConsumerState<PdfToolScreen> createState() => _PdfToolScreenState();
}

class _PdfToolScreenState extends ConsumerState<PdfToolScreen> {
  final List<ToolInput> _inputs = [];
  final TextEditingController _text = TextEditingController();
  final TextEditingController _page = TextEditingController();
  final GlobalKey<SignaturePadState> _signature = GlobalKey();
  int _verticalPosition = 2;
  bool _signOnRight = true;
  PdfCompressionLevel _level = PdfCompressionLevel.balanced;
  int _quarterTurns = 1;
  String? _textError;
  String? _resultMessage;

  PdfTool get _tool => widget.tool;

  bool get _usesImages => _tool == PdfTool.imagesToPdf;

  bool get _multiple => _tool == PdfTool.merge || _usesImages;

  bool get _needsText =>
      _tool == PdfTool.extract ||
      _tool == PdfTool.protect ||
      _tool == PdfTool.unlock ||
      _tool == PdfTool.watermark ||
      _tool == PdfTool.addText;

  bool get _needsPage => _tool == PdfTool.addText || _tool == PdfTool.sign;

  bool get _secretText => _tool == PdfTool.protect || _tool == PdfTool.unlock;

  @override
  void dispose() {
    _text.dispose();
    _page.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = <ToolInput>[];
    if (_usesImages) {
      final images = await ImagePicker().pickMultiImage();
      picked.addAll([
        for (final image in images)
          ToolInput(
            path: image.path,
            name: p.basenameWithoutExtension(image.name),
          ),
      ]);
    } else {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      picked.addAll([
        for (final file in files)
          if (file.path != null)
            ToolInput(
              path: file.path!,
              name: p.basenameWithoutExtension(file.name),
            ),
      ]);
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      if (!_multiple) _inputs.clear();
      _inputs.addAll(_multiple ? picked : picked.take(1));
      _resultMessage = null;
    });
  }

  bool _validate(AppLocalizations l10n) {
    String? error;
    if (_needsText && _text.text.trim().isEmpty) {
      error = switch (_tool) {
        PdfTool.protect || PdfTool.unlock => l10n.toolPasswordRequired,
        _ => l10n.toolTextRequired,
      };
    }
    setState(() => _textError = error);
    return error == null;
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    final core = context.coreL10n;
    if (_tool == PdfTool.merge && _inputs.length < 2) {
      context.showMessage(l10n.toolNeedTwo);
      return;
    }
    if (!_validate(l10n)) return;
    final pageText = _page.text.trim();
    final pageNumber = pageText.isEmpty ? null : int.tryParse(pageText);
    if (_needsPage && pageText.isNotEmpty && pageNumber == null) {
      context.showMessage(l10n.toolPageInvalid);
      return;
    }
    String? signaturePath;
    if (_tool == PdfTool.sign) {
      final png = await _signature.currentState?.toPng();
      if (!mounted) return;
      if (png == null) {
        context.showMessage(l10n.signEmpty);
        return;
      }
      final storage = ref.read(fileStorageProvider);
      signaturePath = storage.absolutePath(
        await storage.writeBytes(StorageArea.temp, png, extension: 'png'),
      );
      if (!mounted) return;
    }

    final runner = ref.read(pdfToolRunnerProvider);
    String? inputPassword;
    Result<ToolOutcome> result;
    // A protected input asks for its password, then the tool runs again.
    while (true) {
      final request = ToolRequest(
        tool: _tool,
        inputs: List.of(_inputs),
        resultName: '${_inputs.first.name} - ${_tool.title(l10n)}',
        text: _secretText ? _text.text : _text.text.trim(),
        level: _level,
        quarterTurns: _quarterTurns,
        inputPassword: inputPassword,
        pageNumber: pageNumber,
        verticalPosition: _verticalPosition,
        signaturePath: signaturePath,
        signOnRight: _signOnRight,
      );
      result = await runWithProgress(
        context,
        message: l10n.toolRunning,
        task: (progress) => runner.run(
          request,
          onProgress: (done, total) =>
              progress.report(total == 0 ? null : done / total),
        ),
      );
      if (!mounted) return;
      final failure = result.failureOrNull;
      final canAskPassword =
          failure != null &&
          needsPassword(failure) &&
          _tool != PdfTool.unlock &&
          _tool != PdfTool.merge;
      if (!canAskPassword) break;
      context.showFailure(failure);
      inputPassword = await showTextInputDialog(
        context,
        title: l10n.toolPasswordOfPdf,
        obscureText: true,
        validator: (value) => value.isEmpty ? l10n.toolPasswordRequired : null,
      );
      if (!mounted || inputPassword == null) return;
    }

    switch (result) {
      case Success(:final value):
        final compression = value.compression;
        final message = compression == null
            ? core.savedToLibrary
            : compression.reduced
            ? l10n.toolCompressionResult(
                formatFileSize(core, compression.originalSize),
                formatFileSize(core, compression.compressedSize),
              )
            : l10n.toolCompressionNone(
                formatFileSize(core, compression.originalSize),
              );
        setState(() {
          _resultMessage = message;
          _inputs.clear();
          _text.clear();
        });
        ref.read(adsServiceProvider).taskCompleted();
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              action: value.documents.isEmpty
                  ? null
                  : SnackBarAction(
                      label: l10n.toolOpenResult,
                      onPressed: () => router.push(
                        AppRoutes.documentDetails(value.documents.first.id),
                      ),
                    ),
            ),
          );
      case Err(:final failure):
        if (failure is! CancelledFailure) context.showFailure(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_tool.title(l10n))),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          Text(_tool.hint(l10n), style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: Icon(_usesImages ? Icons.photo_library_outlined : Icons.add),
            label: Text(_usesImages ? l10n.scannerImport : l10n.toolAddPdf),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final input in _inputs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_tool.icon),
              title: Text(
                input.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: context.coreL10n.actionDelete,
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _inputs.remove(input)),
              ),
            ),
          if (_multiple && !_usesImages)
            Text(
              l10n.toolSelectedCount(_inputs.length),
              style: theme.textTheme.bodySmall,
            ),
          if (_needsText) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _text,
              obscureText: _secretText,
              keyboardType: _tool == PdfTool.extract
                  ? TextInputType.datetime
                  : null,
              onChanged: (_) {
                if (_textError != null) setState(() => _textError = null);
              },
              decoration: InputDecoration(
                labelText: switch (_tool) {
                  PdfTool.extract => l10n.toolRanges,
                  PdfTool.watermark => l10n.toolWatermarkText,
                  PdfTool.addText => l10n.toolText,
                  _ => l10n.toolPassword,
                },
                helperText: _tool == PdfTool.extract
                    ? l10n.toolRangesHint
                    : null,
                errorText: _textError,
              ),
            ),
          ],
          if (_needsPage) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _page,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.toolPage),
            ),
          ],
          if (_tool == PdfTool.addText) ...[
            SectionHeader(title: l10n.toolPosition),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(l10n.posTop)),
                ButtonSegment(value: 1, label: Text(l10n.posMiddle)),
                ButtonSegment(value: 2, label: Text(l10n.posBottom)),
              ],
              selected: {_verticalPosition},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _verticalPosition = value.first),
            ),
          ],
          if (_tool == PdfTool.sign) ...[
            SectionHeader(
              title: l10n.signDraw,
              trailing: TextButton(
                onPressed: () => _signature.currentState?.clear(),
                child: Text(l10n.signClear),
              ),
            ),
            SignaturePad(key: _signature),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.signLeft)),
                ButtonSegment(value: true, label: Text(l10n.signRight)),
              ],
              selected: {_signOnRight},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _signOnRight = value.first),
            ),
          ],
          if (_tool == PdfTool.compress) ...[
            SectionHeader(title: l10n.toolCompressionLevel),
            SegmentedButton<PdfCompressionLevel>(
              segments: [
                for (final level in PdfCompressionLevel.values)
                  ButtonSegment(
                    value: level,
                    label: Text(switch (level) {
                      PdfCompressionLevel.low => l10n.levelLow,
                      PdfCompressionLevel.balanced => l10n.levelBalanced,
                      PdfCompressionLevel.high => l10n.levelHigh,
                    }, textAlign: TextAlign.center),
                  ),
              ],
              selected: {_level},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _level = value.first),
            ),
          ],
          if (_tool == PdfTool.rotate) ...[
            SectionHeader(title: l10n.toolRotation),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 1, label: Text(l10n.rotateRight)),
                ButtonSegment(value: 2, label: Text(l10n.rotateHalf)),
                ButtonSegment(value: 3, label: Text(l10n.rotateLeft)),
              ],
              selected: {_quarterTurns},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _quarterTurns = value.first),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _inputs.isEmpty ? null : _run,
            icon: Icon(_tool.icon),
            label: Text(
              _tool == PdfTool.merge ? l10n.toolMergeNow : _tool.title(l10n),
            ),
          ),
          if (_resultMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBanner(message: _resultMessage!, tone: InfoBannerTone.success),
          ],
        ],
      ),
    );
  }
}
