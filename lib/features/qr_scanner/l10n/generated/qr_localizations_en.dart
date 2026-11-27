// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'qr_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class QrLocalizationsEn extends QrLocalizations {
  QrLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get qrScanTitle => 'Scan a QR code';

  @override
  String get barcodeScanTitle => 'Scan a barcode';

  @override
  String get qrScanHint => 'Read a QR code, Data Matrix, Aztec or PDF417';

  @override
  String get barcodeScanHint => 'Read an EAN, UPC, Code 128 or Code 39 code';

  @override
  String get qrHistoryTitle => 'Code history';

  @override
  String get qrHistoryHint => 'Scanned and created codes';

  @override
  String get qrGeneratorTitle => 'Create a QR code';

  @override
  String get qrGeneratorHint => 'Text, link, Wi-Fi, contact…';

  @override
  String get barcodeGeneratorTitle => 'Create a barcode';

  @override
  String get barcodeGeneratorHint =>
      'EAN, UPC, Code 128, Code 39, Data Matrix…';

  @override
  String get qrTorch => 'Torch';

  @override
  String get qrImport => 'Read from an image';

  @override
  String get qrNoCodeInImage => 'No readable code in this image.';

  @override
  String get qrPermissionDenied => 'Camera access is required to read a code.';

  @override
  String get qrCameraError => 'The camera could not start.';

  @override
  String get qrZoom => 'Zoom';

  @override
  String get qrResultTitle => 'Code read';

  @override
  String qrFormat(String format) {
    return 'Format: $format';
  }

  @override
  String get qrOpen => 'Open';

  @override
  String get qrOpenConfirmTitle => 'Open this link?';

  @override
  String get qrOpenFailed => 'No app can open this content.';

  @override
  String get qrBlocked =>
      'This kind of link is blocked for safety and cannot be opened.';

  @override
  String get qrSafe => 'No suspicious sign detected. Still, check the address.';

  @override
  String get qrCaution => 'Be careful:';

  @override
  String get qrDangerous => 'Potentially dangerous link:';

  @override
  String get riskNoTls => 'unencrypted connection (http)';

  @override
  String get riskIpHost => 'IP address instead of a site name';

  @override
  String get riskPunycode => 'site name with misleading characters';

  @override
  String get riskUserInfo => 'hidden identifier before the \"@\"';

  @override
  String get riskManySubdomains => 'too many subdomains';

  @override
  String get riskShortener => 'shortened link hiding its destination';

  @override
  String get riskPort => 'unusual port';

  @override
  String get riskLong => 'abnormally long address';

  @override
  String get riskExecutable => 'program download';

  @override
  String get typeUrl => 'Link';

  @override
  String get typeWifi => 'Wi-Fi network';

  @override
  String get typeEmail => 'E-mail';

  @override
  String get typePhone => 'Phone';

  @override
  String get typeSms => 'SMS';

  @override
  String get typeGeo => 'Location';

  @override
  String get typeContact => 'Contact';

  @override
  String get typeEvent => 'Event';

  @override
  String get typeProduct => 'Product code';

  @override
  String get typeText => 'Text';

  @override
  String wifiNetwork(String name) {
    return 'Network: $name';
  }

  @override
  String wifiPassword(String password) {
    return 'Password: $password';
  }

  @override
  String get wifiCopyPassword => 'Copy password';

  @override
  String get productSearch => 'Search this product on the Web';

  @override
  String get historyEmpty => 'No codes yet';

  @override
  String get historyClear => 'Clear history';

  @override
  String get historyClearConfirm => 'Clear the whole history?';

  @override
  String get historyScanned => 'Scanned';

  @override
  String get historyGenerated => 'Created';

  @override
  String get historyAll => 'All';

  @override
  String get genFormat => 'Format';

  @override
  String get genContent => 'Code content';

  @override
  String genInvalid(String format) {
    return 'This content is not valid for the $format format.';
  }

  @override
  String get genEmpty => 'Enter the content of the code.';

  @override
  String get genColor => 'Colour';

  @override
  String get genLowContrast => 'Low contrast: this code may not be readable.';

  @override
  String get genSave => 'Save as PNG';

  @override
  String get genSaved => 'Image saved to your documents';

  @override
  String get genTemplateText => 'Text';

  @override
  String get genTemplateUrl => 'Link';

  @override
  String get genTemplateWifi => 'Wi-Fi';

  @override
  String get genTemplateEmail => 'E-mail';

  @override
  String get genTemplatePhone => 'Phone';

  @override
  String get genWifiName => 'Network name';

  @override
  String get genWifiPassword => 'Network password';
}
