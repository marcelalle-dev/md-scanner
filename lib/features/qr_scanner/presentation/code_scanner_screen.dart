import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/services/platform_bridge.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/qr_scanner/data/code_history_repository.dart';
import 'package:md_scanner/features/qr_scanner/l10n/generated/qr_localizations.dart';
import 'package:md_scanner/features/qr_scanner/presentation/code_result_sheet.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const List<BarcodeFormat> _matrixFormats = [
  BarcodeFormat.qrCode,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.aztec,
  BarcodeFormat.pdf417,
];

const List<BarcodeFormat> _linearFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
];

String barcodeFormatLabel(BarcodeFormat format) => switch (format) {
  BarcodeFormat.qrCode => 'QR Code',
  BarcodeFormat.dataMatrix => 'Data Matrix',
  BarcodeFormat.aztec => 'Aztec',
  BarcodeFormat.pdf417 => 'PDF417',
  BarcodeFormat.ean13 => 'EAN-13',
  BarcodeFormat.ean8 => 'EAN-8',
  BarcodeFormat.upcA => 'UPC-A',
  BarcodeFormat.upcE => 'UPC-E',
  BarcodeFormat.code128 => 'Code 128',
  BarcodeFormat.code39 => 'Code 39',
  _ => format.name,
};

/// Camera scanner for 2D codes ([linear] false) or 1D barcodes ([linear]
/// true). Scanning pauses while a result is displayed.
class CodeScannerScreen extends ConsumerStatefulWidget {
  const CodeScannerScreen({required this.linear, super.key});

  final bool linear;

  @override
  ConsumerState<CodeScannerScreen> createState() => _CodeScannerScreenState();
}

class _CodeScannerScreenState extends ConsumerState<CodeScannerScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: _formats,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _showingResult = false;
  double _zoom = 0;

  List<BarcodeFormat> get _formats =>
      widget.linear ? _linearFormats : _matrixFormats;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handle(Barcode barcode) async {
    final value = barcode.rawValue;
    if (value == null || value.isEmpty || _showingResult) return;
    _showingResult = true;
    await _controller.stop();
    final format = barcodeFormatLabel(barcode.format);
    await ref
        .read(codeHistoryRepositoryProvider)
        .add(content: value, format: format, kind: CodeHistoryKind.scanned);
    if (!mounted) return;
    await showCodeResultSheet(
      context,
      rawValue: value,
      format: format,
      linearBarcode: _linearFormats.contains(barcode.format),
    );
    _showingResult = false;
    if (mounted) await _controller.start();
  }

  Future<void> _importImage() async {
    final l10n = QrLocalizations.of(context);
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final capture = await _controller.analyzeImage(
      image.path,
      formats: _formats,
    );
    if (!mounted) return;
    final barcodes = capture?.barcodes ?? const <Barcode>[];
    if (barcodes.isEmpty) {
      context.showMessage(l10n.qrNoCodeInImage);
      return;
    }
    await _handle(barcodes.first);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = QrLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.linear ? l10n.barcodeScanTitle : l10n.qrScanTitle),
        actions: [
          IconButton(
            tooltip: l10n.qrImport,
            icon: const Icon(Icons.image_search_outlined),
            onPressed: _importImage,
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
              tooltip: l10n.qrTorch,
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off_outlined,
              ),
              onPressed: state.torchState == TorchState.unavailable
                  ? null
                  : _controller.toggleTorch,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (capture.barcodes.isNotEmpty) {
                  _handle(capture.barcodes.first);
                }
              },
              errorBuilder: (context, error) {
                final denied =
                    error.errorCode == MobileScannerErrorCode.permissionDenied;
                return EmptyState(
                  icon: Icons.no_photography_outlined,
                  title: denied ? l10n.qrPermissionDenied : l10n.qrCameraError,
                  action: denied
                      ? OutlinedButton(
                          onPressed: () => ref
                              .read(platformBridgeProvider)
                              .openAppSettings(),
                          child: Text(context.coreL10n.actionOpenSettings),
                        )
                      : null,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.zoom_out, size: 20),
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      label: l10n.qrZoom,
                      onChanged: (value) {
                        setState(() => _zoom = value);
                        _controller.setZoomScale(value);
                      },
                    ),
                  ),
                  const Icon(Icons.zoom_in, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
