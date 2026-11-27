import 'package:flutter/material.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';

/// The PDF tools offered in the Tools tab. [id] is the route parameter.
enum PdfTool {
  imagesToPdf('images-to-pdf', Icons.collections_outlined),
  merge('merge', Icons.merge_outlined),
  extract('extract', Icons.content_cut_outlined),
  compress('compress', Icons.compress_outlined),
  rotate('rotate', Icons.rotate_90_degrees_cw_outlined),
  protect('protect', Icons.lock_outline),
  unlock('unlock', Icons.lock_open_outlined),
  watermark('watermark', Icons.branding_watermark_outlined),
  pageNumbers('page-numbers', Icons.format_list_numbered_outlined),
  addText('add-text', Icons.text_fields),
  sign('sign', Icons.draw_outlined),
  pdfToImages('pdf-to-images', Icons.image_outlined);

  const PdfTool(this.id, this.icon);

  final String id;
  final IconData icon;

  static PdfTool? byId(String? id) {
    for (final tool in values) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  String title(AppLocalizations l10n) => switch (this) {
    imagesToPdf => l10n.toolImagesToPdf,
    merge => l10n.toolMerge,
    extract => l10n.toolSplit,
    compress => l10n.toolCompress,
    rotate => l10n.toolRotate,
    protect => l10n.toolProtect,
    unlock => l10n.toolUnlock,
    watermark => l10n.toolWatermark,
    pageNumbers => l10n.toolPageNumbers,
    addText => l10n.toolAddText,
    sign => l10n.toolSign,
    pdfToImages => l10n.toolPdfToImages,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    imagesToPdf => l10n.toolImagesToPdfHint,
    merge => l10n.toolMergeHint,
    extract => l10n.toolSplitHint,
    compress => l10n.toolCompressHint,
    rotate => l10n.toolRotateHint,
    protect => l10n.toolProtectHint,
    unlock => l10n.toolUnlockHint,
    watermark => l10n.toolWatermarkHint,
    pageNumbers => l10n.toolPageNumbersHint,
    addText => l10n.toolAddTextHint,
    sign => l10n.toolSignHint,
    pdfToImages => l10n.toolPdfToImagesHint,
  };
}
