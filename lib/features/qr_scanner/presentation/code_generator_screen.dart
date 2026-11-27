import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/features/qr_scanner/data/code_history_repository.dart';
import 'package:md_scanner/features/qr_scanner/l10n/generated/qr_localizations.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';

/// Symbologies the generator can produce.
enum GeneratorFormat {
  qr('QR Code', linear: false),
  dataMatrix('Data Matrix', linear: false),
  aztec('Aztec', linear: false),
  pdf417('PDF417', linear: false),
  ean13('EAN-13'),
  ean8('EAN-8'),
  upcA('UPC-A'),
  upcE('UPC-E'),
  code128('Code 128'),
  code39('Code 39');

  const GeneratorFormat(this.label, {this.linear = true});

  final String label;
  final bool linear;

  Barcode get barcode => switch (this) {
    qr => Barcode.qrCode(),
    dataMatrix => Barcode.dataMatrix(),
    aztec => Barcode.aztec(),
    pdf417 => Barcode.pdf417(),
    ean13 => Barcode.ean13(),
    ean8 => Barcode.ean8(),
    upcA => Barcode.upcA(),
    upcE => Barcode.upcE(),
    code128 => Barcode.code128(),
    code39 => Barcode.code39(),
  };

  /// True when [data] can be encoded in this symbology (charset, length,
  /// check digit).
  bool accepts(String data) => data.isNotEmpty && barcode.isValid(data);
}

enum QrTemplate { text, url, wifi, email, phone }

/// Builds the standard payload of a QR template.
String buildQrPayload(
  QrTemplate template,
  String value, {
  String wifiPassword = '',
}) {
  final text = value.trim();
  if (text.isEmpty) return '';
  String escape(String input) =>
      input.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
  return switch (template) {
    QrTemplate.text => text,
    QrTemplate.url => text.contains('://') ? text : 'https://$text',
    QrTemplate.email => 'mailto:$text',
    QrTemplate.phone => 'tel:${text.replaceAll(' ', '')}',
    QrTemplate.wifi =>
      wifiPassword.isEmpty
          ? 'WIFI:T:nopass;S:${escape(text)};;'
          : 'WIFI:T:WPA;S:${escape(text)};P:${escape(wifiPassword)};;',
  };
}

const List<Color> _codeColors = [
  Colors.black,
  Color(0xFF0B1F3A),
  Color(0xFF1F6BFF),
  Color(0xFF1E7A4C),
  Color(0xFF8E1F3A),
];

/// Generator for QR codes ([qrMode] true) or other barcodes.
class CodeGeneratorScreen extends ConsumerStatefulWidget {
  const CodeGeneratorScreen({required this.qrMode, super.key});

  final bool qrMode;

  @override
  ConsumerState<CodeGeneratorScreen> createState() =>
      _CodeGeneratorScreenState();
}

class _CodeGeneratorScreenState extends ConsumerState<CodeGeneratorScreen> {
  final GlobalKey _previewKey = GlobalKey();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _wifiPassword = TextEditingController();
  late GeneratorFormat _format = widget.qrMode
      ? GeneratorFormat.qr
      : GeneratorFormat.ean13;
  QrTemplate _template = QrTemplate.text;
  Color _color = Colors.black;
  bool _saving = false;

  @override
  void dispose() {
    _value.dispose();
    _wifiPassword.dispose();
    super.dispose();
  }

  String get _data => widget.qrMode
      ? buildQrPayload(_template, _value.text, wifiPassword: _wifiPassword.text)
      : _value.text.trim();

  Future<void> _save() async {
    final l10n = QrLocalizations.of(context);
    final data = _data;
    final boundary =
        _previewKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || _saving) return;
    setState(() => _saving = true);
    final storage = ref.read(fileStorageProvider);
    String? path;
    final result = await guard(() async {
      final image = await boundary.toImage(pixelRatio: 4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) {
        throw const FailureException(
          ImageFailure(ImageFailureKind.processingFailed),
        );
      }
      path = await storage.writeBytes(
        StorageArea.documents,
        bytes.buffer.asUint8List(),
        extension: 'png',
      );
      final document = await ref
          .read(documentRepositoryProvider)
          .register(
            NewDocument(
              name:
                  '${_format.label} ${data.length > 24 ? data.substring(0, 24) : data}',
              filePath: path!,
              fileType: DocumentFileType.png,
              source: DocumentSource.generated,
              pageCount: 1,
            ),
          );
      if (document case Err(:final failure)) throw FailureException(failure);
      await ref
          .read(codeHistoryRepositoryProvider)
          .add(
            content: data,
            format: _format.label,
            kind: CodeHistoryKind.generated,
          );
    });
    if (result.isFailure && path != null) await storage.delete(path!);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Success():
        context.showMessage(l10n.genSaved);
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  String _templateLabel(QrLocalizations l10n, QrTemplate template) =>
      switch (template) {
        QrTemplate.text => l10n.genTemplateText,
        QrTemplate.url => l10n.genTemplateUrl,
        QrTemplate.wifi => l10n.genTemplateWifi,
        QrTemplate.email => l10n.genTemplateEmail,
        QrTemplate.phone => l10n.genTemplatePhone,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = QrLocalizations.of(context);
    final theme = Theme.of(context);
    final customColors = ref.watch(
      hasPremiumFeatureProvider(PremiumFeature.advancedCustomization),
    );
    final data = _data;
    final valid = _format.accepts(data);
    final formats = [
      for (final format in GeneratorFormat.values)
        if (widget.qrMode == (format == GeneratorFormat.qr)) format,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.qrMode ? l10n.qrGeneratorTitle : l10n.barcodeGeneratorTitle,
        ),
      ),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          if (widget.qrMode)
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final template in QrTemplate.values)
                  ChoiceChip(
                    label: Text(_templateLabel(l10n, template)),
                    selected: _template == template,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _template = template),
                  ),
              ],
            )
          else
            DropdownMenu<GeneratorFormat>(
              initialSelection: _format,
              label: Text(l10n.genFormat),
              expandedInsets: EdgeInsets.zero,
              onSelected: (format) {
                if (format != null) setState(() => _format = format);
              },
              dropdownMenuEntries: [
                for (final format in formats)
                  DropdownMenuEntry(value: format, label: format.label),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _value,
            onChanged: (_) => setState(() {}),
            keyboardType: switch ((widget.qrMode, _template)) {
              (true, QrTemplate.url) => TextInputType.url,
              (true, QrTemplate.email) => TextInputType.emailAddress,
              (true, QrTemplate.phone) => TextInputType.phone,
              _ => null,
            },
            maxLines: widget.qrMode && _template == QrTemplate.text ? 3 : 1,
            decoration: InputDecoration(
              labelText: widget.qrMode && _template == QrTemplate.wifi
                  ? l10n.genWifiName
                  : l10n.genContent,
              errorText: data.isNotEmpty && !valid
                  ? l10n.genInvalid(_format.label)
                  : null,
              errorMaxLines: 2,
            ),
          ),
          if (widget.qrMode && _template == QrTemplate.wifi) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _wifiPassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.genWifiPassword),
            ),
          ],
          SectionHeader(title: l10n.genColor),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final color in _codeColors)
                Semantics(
                  button: true,
                  selected: _color == color,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      // Black is always free; other colours are a Premium
                      // customization.
                      if (color == Colors.black || customColors) {
                        setState(() => _color = color);
                      } else {
                        context.push(AppRoutes.premium);
                      }
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == color
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.outlineVariant,
                          width: _color == color ? 3 : 1,
                        ),
                      ),
                      child: color != Colors.black && !customColors
                          ? const PremiumBadge(compact: true)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: valid
                ? RepaintBoundary(
                    key: _previewKey,
                    // White background and margin: the quiet zone a reader
                    // needs around the code.
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: BarcodeWidget(
                        barcode: _format.barcode,
                        data: data,
                        color: _color,
                        width: _format.linear ? 280 : 220,
                        height: _format.linear ? 120 : 220,
                        style: const TextStyle(color: Colors.black),
                        errorBuilder: (context, error) => Text(
                          l10n.genInvalid(_format.label),
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      data.isEmpty
                          ? l10n.genEmpty
                          : l10n.genInvalid(_format.label),
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: valid && !_saving ? _save : null,
            icon: const Icon(Icons.save_alt_outlined),
            label: Text(l10n.genSave),
          ),
        ],
      ),
    );
  }
}
