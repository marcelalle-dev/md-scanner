/// Every route of the app. Screens navigate with these constants only:
/// `context.push(AppRoutes.ocr)` or `context.go(AppRoutes.home)`.
///
/// Routes taking an identifier expose a builder (`documentDetails(id)`).
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';

  // Bottom navigation branches.
  static const String home = '/home';
  static const String scanner = '/scanner';
  static const String tools = '/tools';
  static const String documents = '/documents';
  static const String profile = '/profile';

  // Document scanner flow.
  static const String scanCamera = '/scan/camera';
  static const String scanPreview = '/scan/preview';
  static const String scanPages = '/scan/pages';
  static const String scanExport = '/scan/export';

  // Image editor (pushed with an ImageEditRequest as `extra`).
  static const String imageCrop = '/image/crop';
  static const String imageEdit = '/image/edit';

  // OCR.
  static const String ocr = '/ocr';

  // PDF tools.
  static const String pdfTools = '/pdf';
  static const String pdfViewer = '/pdf/viewer';
  static const String pdfEditor = '/pdf/editor';
  static String pdfTool(String toolId) => '/pdf/tool/$toolId';
  static const String pdfToolPattern = '/pdf/tool/:toolId';

  // Codes.
  static const String qrScanner = '/codes/qr-scanner';
  static const String barcodeScanner = '/codes/barcode-scanner';
  static const String codeHistory = '/codes/history';
  static const String qrGenerator = '/codes/qr-generator';
  static const String barcodeGenerator = '/codes/barcode-generator';

  // Library.
  static String folder(String folderId) => '/documents/folder/$folderId';
  static const String folderPattern = '/documents/folder/:folderId';
  static const String documentSearch = '/documents/search';
  static String documentDetails(String documentId) =>
      '/documents/item/$documentId';
  static const String documentDetailsPattern = '/documents/item/:documentId';
  static const String trash = '/documents/trash';

  // ID scanner.
  static const String idScanner = '/id-scanner';

  // Vault and security.
  static const String vault = '/vault';
  static const String securityCenter = '/security';
  static const String pinSetup = '/security/pin';

  // AI assistant.
  static const String aiAssistant = '/assistant';

  // Premium.
  static const String premium = '/premium';

  // Profile area.
  static const String settings = '/settings';
  static const String privacy = '/privacy';
  static const String help = '/help';

  /// Query parameter carrying a document id to routes that accept one
  /// (`/ocr?documentId=…`, `/pdf/viewer?documentId=…`, `/assistant?documentId=…`).
  static const String documentIdParam = 'documentId';

  static String withDocument(String route, String documentId) => Uri(
    path: route,
    queryParameters: {documentIdParam: documentId},
  ).toString();
}
