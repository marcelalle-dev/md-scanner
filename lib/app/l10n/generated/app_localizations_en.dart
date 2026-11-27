// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navScanner => 'Scanner';

  @override
  String get navTools => 'Tools';

  @override
  String get navDocuments => 'Documents';

  @override
  String get navProfile => 'Profile';

  @override
  String get homeTagline => 'Scan, organize, share.';

  @override
  String get homeScan => 'Scan';

  @override
  String get homeImport => 'Import';

  @override
  String get homePdfTools => 'Tools';

  @override
  String get homeRecent => 'Recent documents';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeEmptyTitle => 'No documents yet';

  @override
  String get homeEmptyMessage =>
      'Scan your first document: it will show up here.';

  @override
  String get scannerTitle => 'Scanner';

  @override
  String get scannerMode => 'Document type';

  @override
  String get modeDocument => 'Document';

  @override
  String get modeReceipt => 'Receipt';

  @override
  String get modeBook => 'Book';

  @override
  String get modeWhiteboard => 'Whiteboard';

  @override
  String get modeIdCard => 'ID document';

  @override
  String get scannerStart => 'Scan with the camera';

  @override
  String get scannerImport => 'Import from gallery';

  @override
  String get scannerHint =>
      'With the camera, edge detection and cropping are handled by Google\'s document scanner. For imported photos, MD SCANNER detects and straightens the document itself.';

  @override
  String get scannerPreparing => 'Preparing pages…';

  @override
  String get reviewTitle => 'Scanned pages';

  @override
  String get reviewName => 'Document name';

  @override
  String reviewDefaultName(String date) {
    return 'Scan $date';
  }

  @override
  String get reviewAddCamera => 'Add with the camera';

  @override
  String get reviewAddGallery => 'Add from gallery';

  @override
  String get reviewExportPdf => 'Save as PDF';

  @override
  String get reviewExportImages => 'Save as JPG images';

  @override
  String get reviewExporting => 'Creating document…';

  @override
  String reviewPage(int number) {
    return 'Page $number';
  }

  @override
  String get reviewDeletePage => 'Delete page';

  @override
  String get reviewDuplicate => 'Duplicate page';

  @override
  String get reviewRotate => 'Rotate';

  @override
  String get reviewMoveUp => 'Move up';

  @override
  String get reviewMoveDown => 'Move down';

  @override
  String get reviewFilter => 'Filter';

  @override
  String get reviewCropAuto => 'Automatic crop applied';

  @override
  String get reviewCropNone => 'Outline not detected: page kept whole';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterEnhanced => 'Enhanced colour';

  @override
  String get filterGrayscale => 'Grayscale';

  @override
  String get filterBlackAndWhite => 'Black and white';

  @override
  String get filterReadability => 'Readability';

  @override
  String get filterNoShadow => 'No shadows';

  @override
  String get reviewDiscardTitle => 'Discard this scan?';

  @override
  String get reviewDiscardMessage => 'Unsaved pages will be lost.';

  @override
  String get reviewDiscard => 'Discard';

  @override
  String reviewImagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images saved',
      one: '1 image saved',
    );
    return '$_temp0';
  }

  @override
  String get documentsTitle => 'Documents';

  @override
  String get documentsSearch => 'Search by name';

  @override
  String get documentsEmptyTitle => 'Your library is empty';

  @override
  String get documentsEmptyMessage =>
      'Documents you scan, import or create with the tools show up here.';

  @override
  String get documentsNoResult => 'No matching document';

  @override
  String get documentsSort => 'Sort';

  @override
  String get sortNewest => 'Newest first';

  @override
  String get sortOldest => 'Oldest first';

  @override
  String get sortName => 'Name (A to Z)';

  @override
  String get sortSize => 'Size (largest first)';

  @override
  String get documentsFavoritesOnly => 'Favorites';

  @override
  String get documentsTrash => 'Trash';

  @override
  String get documentsImport => 'Import a file';

  @override
  String get documentsImported => 'File imported';

  @override
  String get documentRename => 'Rename';

  @override
  String get documentFavorite => 'Add to favorites';

  @override
  String get documentUnfavorite => 'Remove from favorites';

  @override
  String get documentMoveToTrash => 'Move to trash';

  @override
  String get documentMovedToTrash => 'Document moved to trash';

  @override
  String get documentNameEmpty => 'The name cannot be empty.';

  @override
  String get documentPreviewUnavailable =>
      'No preview for this file type. Use Share to open it in another app.';

  @override
  String get trashTitle => 'Trash';

  @override
  String get trashEmpty => 'The trash is empty';

  @override
  String get trashRestore => 'Restore';

  @override
  String get trashDeleteForever => 'Delete permanently';

  @override
  String get trashEmptyAll => 'Empty trash';

  @override
  String get trashConfirmTitle => 'Delete permanently?';

  @override
  String get trashConfirmMessage => 'This cannot be undone.';

  @override
  String get toolsTitle => 'Tools';

  @override
  String get toolsSectionText => 'Text';

  @override
  String get toolsSectionCodes => 'QR codes and barcodes';

  @override
  String get toolsSectionPdf => 'PDF';

  @override
  String get toolsSectionSecurity => 'Security';

  @override
  String get toolImagesToPdf => 'Images to PDF';

  @override
  String get toolImagesToPdfHint => 'Combine photos into one PDF';

  @override
  String get toolMerge => 'Merge PDFs';

  @override
  String get toolMergeHint => 'Join several PDFs into one';

  @override
  String get toolSplit => 'Extract pages';

  @override
  String get toolSplitHint => 'Create a PDF from chosen pages';

  @override
  String get toolCompress => 'Compress';

  @override
  String get toolCompressHint => 'Reduce the size of a PDF';

  @override
  String get toolRotate => 'Rotate pages';

  @override
  String get toolRotateHint => 'Turn every page';

  @override
  String get toolProtect => 'Password protect';

  @override
  String get toolProtectHint => 'AES 256-bit encryption';

  @override
  String get toolUnlock => 'Unlock';

  @override
  String get toolUnlockHint => 'Remove the password of a PDF when you know it';

  @override
  String get toolWatermark => 'Watermark';

  @override
  String get toolWatermarkHint => 'Add translucent text';

  @override
  String get toolPageNumbers => 'Number pages';

  @override
  String get toolPageNumbersHint => 'Add \"page / total\" at the bottom';

  @override
  String get toolPdfToImages => 'PDF to images';

  @override
  String get toolPdfToImagesHint => 'Save each page as a JPG';

  @override
  String get toolAddPdf => 'Add a PDF';

  @override
  String toolSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDFs selected',
      one: '1 PDF selected',
      zero: 'No PDF selected',
    );
    return '$_temp0';
  }

  @override
  String get toolNeedTwo => 'Select at least two PDFs.';

  @override
  String get toolMergeNow => 'Merge';

  @override
  String get toolRanges => 'Pages to extract';

  @override
  String get toolRangesHint => 'Example: 1-3,5,8-';

  @override
  String get toolPassword => 'Password';

  @override
  String get toolPasswordRequired => 'Enter a password.';

  @override
  String get toolPasswordOfPdf => 'Password of the PDF';

  @override
  String get toolWatermarkText => 'Watermark text';

  @override
  String get toolTextRequired => 'Enter some text.';

  @override
  String get toolCompressionLevel => 'Compression level';

  @override
  String get levelLow => 'Low — best quality';

  @override
  String get levelBalanced => 'Balanced';

  @override
  String get levelHigh => 'High — smallest file';

  @override
  String get toolRotation => 'Rotation';

  @override
  String get rotateRight => '90° clockwise';

  @override
  String get rotateHalf => '180°';

  @override
  String get rotateLeft => '90° counter-clockwise';

  @override
  String get toolRunning => 'Processing PDF…';

  @override
  String toolCompressionResult(String before, String after) {
    return 'Size reduced: $before → $after';
  }

  @override
  String toolCompressionNone(String size) {
    return 'This PDF is already optimized: no reduction achieved ($size).';
  }

  @override
  String get toolOpenResult => 'Open';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileAppearance => 'Appearance';

  @override
  String get themeSystem => 'Automatic';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get profileLanguage => 'Language';

  @override
  String get languageSystem => 'System language';

  @override
  String get profileStorage => 'Storage used';

  @override
  String get profileBackup => 'Backup';

  @override
  String get backupExport => 'Export a backup';

  @override
  String get backupExportHint =>
      'Creates an archive of your documents to share or save';

  @override
  String get backupRestore => 'Restore a backup';

  @override
  String get backupRestoreHint =>
      'Adds the documents of an archive to the library';

  @override
  String get backupExporting => 'Creating backup…';

  @override
  String get backupRestoring => 'Restoring…';

  @override
  String get backupRestored => 'Backup restored';

  @override
  String get profileAbout => 'About';

  @override
  String get profilePrivacy => 'Privacy policy';

  @override
  String get profileHelp => 'Help and support';

  @override
  String get profileLicenses => 'Open-source licenses';

  @override
  String profileVersion(String version) {
    return 'Version $version';
  }

  @override
  String get profilePublisher => 'Published by MarcelAlle.Dev';

  @override
  String get onbTitle1 => 'Scan in one tap';

  @override
  String get onbText1 =>
      'Take a picture of a document: edges are detected, the page is straightened and saved as a PDF.';

  @override
  String get onbTitle2 => 'All your tools in one place';

  @override
  String get onbText2 =>
      'Text recognition, QR codes, merging, compression, signing and protection of your PDFs.';

  @override
  String get onbTitle3 => 'Your documents stay with you';

  @override
  String get onbText3 =>
      'Everything is processed on the device and works offline. An encrypted vault protects your sensitive documents.';

  @override
  String get onbStart => 'Get started';

  @override
  String get foldersTitle => 'Folders';

  @override
  String get folderNew => 'New folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get folderDelete => 'Delete folder';

  @override
  String folderDeleteConfirm(String name) {
    return 'Delete the folder \"$name\"?';
  }

  @override
  String get folderDeleteMessage =>
      'Its documents move back to the root. No document is deleted.';

  @override
  String get folderEmpty => 'This folder is empty';

  @override
  String get documentMove => 'Move to…';

  @override
  String get folderRoot => 'Root (no folder)';

  @override
  String get documentMoved => 'Document moved';

  @override
  String get documentTags => 'Tags…';

  @override
  String get tagsHint => 'Separate tags with commas';

  @override
  String get tagsLabel => 'Tags';

  @override
  String get reviewCrop => 'Crop';

  @override
  String get cropTitle => 'Crop the page';

  @override
  String get cropHint =>
      'Drag the four corners onto the edges of the document.';

  @override
  String get cropReset => 'Whole page';

  @override
  String get cropInvalid =>
      'Place the corners so that they form a quadrilateral.';

  @override
  String get toolAddText => 'Add text';

  @override
  String get toolAddTextHint => 'Write one line on a page';

  @override
  String get toolSign => 'Sign';

  @override
  String get toolSignHint => 'Place a handwritten signature';

  @override
  String get toolPage => 'Page number';

  @override
  String get toolPageInvalid => 'Invalid page number.';

  @override
  String get toolText => 'Text to add';

  @override
  String get toolPosition => 'Position';

  @override
  String get posTop => 'Top';

  @override
  String get posMiddle => 'Middle';

  @override
  String get posBottom => 'Bottom';

  @override
  String get signDraw => 'Sign inside the frame';

  @override
  String get signClear => 'Clear';

  @override
  String get signEmpty => 'Draw your signature.';

  @override
  String get signLeft => 'Bottom left';

  @override
  String get signRight => 'Bottom right';

  @override
  String get printFailed => 'Printing could not start.';

  @override
  String get reviewAdjust => 'Adjust';

  @override
  String get adjustBrightness => 'Brightness';

  @override
  String get adjustContrast => 'Contrast';

  @override
  String get adjustSaturation => 'Saturation';

  @override
  String get adjustReset => 'Reset';

  @override
  String get wipeTitle => 'Erase all my data';

  @override
  String get wipeHint => 'Documents, vault, histories, PIN and settings';

  @override
  String get wipeConfirmTitle => 'Erase everything?';

  @override
  String get wipeConfirmMessage =>
      'All your documents, including those in the vault, the histories, the PIN and your settings will be permanently deleted from this device. This cannot be undone.\n\nYour Premium subscription, managed by Google Play, is not affected.';

  @override
  String get wipeConfirm => 'Erase everything';

  @override
  String get wipeRunning => 'Erasing…';

  @override
  String get wipeDone => 'All your data has been erased';
}
