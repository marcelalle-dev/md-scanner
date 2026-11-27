import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/shell/app_shell.dart';
import 'package:md_scanner/features/ai_assistant/presentation/ai_assistant_screen.dart';
import 'package:md_scanner/features/document_scanner/presentation/scan_review_screen.dart';
import 'package:md_scanner/features/document_scanner/presentation/scanner_screen.dart';
import 'package:md_scanner/features/document_vault/presentation/document_details_screen.dart';
import 'package:md_scanner/features/document_vault/presentation/documents_screen.dart';
import 'package:md_scanner/features/document_vault/presentation/trash_screen.dart';
import 'package:md_scanner/features/home/presentation/home_screen.dart';
import 'package:md_scanner/features/id_scanner/presentation/id_scanner_screen.dart';
import 'package:md_scanner/features/ocr/presentation/ocr_screen.dart';
import 'package:md_scanner/features/onboarding/presentation/onboarding_screen.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool_screen.dart';
import 'package:md_scanner/features/pdf_tools/presentation/tools_screen.dart';
import 'package:md_scanner/features/premium/presentation/premium_screen.dart';
import 'package:md_scanner/features/qr_scanner/presentation/code_generator_screen.dart';
import 'package:md_scanner/features/qr_scanner/presentation/code_history_screen.dart';
import 'package:md_scanner/features/qr_scanner/presentation/code_scanner_screen.dart';
import 'package:md_scanner/features/security/presentation/vault_screen.dart';
import 'package:md_scanner/features/settings/presentation/profile_screen.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    // First launch goes through the introduction; afterwards it is skipped.
    redirect: (context, state) {
      final onboarded = ref.read(appSettingsProvider).onboardingCompleted;
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (!onboarded && !atOnboarding) return AppRoutes.onboarding;
      if (onboarded && atOnboarding) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.folderPattern,
        builder: (context, state) =>
            DocumentsScreen(folderId: state.pathParameters['folderId']),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          _branch(AppRoutes.home, const HomeScreen()),
          _branch(AppRoutes.scanner, const ScannerScreen()),
          _branch(AppRoutes.tools, const ToolsScreen()),
          _branch(AppRoutes.documents, const DocumentsScreen()),
          _branch(AppRoutes.profile, const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: AppRoutes.scanPages,
        builder: (context, state) => const ScanReviewScreen(),
      ),
      GoRoute(
        path: AppRoutes.documentDetailsPattern,
        builder: (context, state) => DocumentDetailsScreen(
          documentId: state.pathParameters['documentId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.idScanner,
        builder: (context, state) => const IdScannerScreen(),
      ),
      GoRoute(
        path: AppRoutes.ocr,
        builder: (context, state) => OcrScreen(
          documentId: state.uri.queryParameters[AppRoutes.documentIdParam],
        ),
      ),
      GoRoute(
        path: AppRoutes.qrScanner,
        builder: (context, state) => const CodeScannerScreen(linear: false),
      ),
      GoRoute(
        path: AppRoutes.barcodeScanner,
        builder: (context, state) => const CodeScannerScreen(linear: true),
      ),
      GoRoute(
        path: AppRoutes.codeHistory,
        builder: (context, state) => const CodeHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.qrGenerator,
        builder: (context, state) => const CodeGeneratorScreen(qrMode: true),
      ),
      GoRoute(
        path: AppRoutes.barcodeGenerator,
        builder: (context, state) => const CodeGeneratorScreen(qrMode: false),
      ),
      GoRoute(
        path: AppRoutes.aiAssistant,
        builder: (context, state) => AiAssistantScreen(
          documentId: state.uri.queryParameters[AppRoutes.documentIdParam],
        ),
      ),
      GoRoute(
        path: AppRoutes.premium,
        builder: (context, state) => const PremiumScreen(),
      ),
      GoRoute(
        path: AppRoutes.vault,
        builder: (context, state) => const VaultScreen(),
      ),
      GoRoute(
        path: AppRoutes.trash,
        builder: (context, state) => const TrashScreen(),
      ),
      GoRoute(
        path: AppRoutes.pdfToolPattern,
        redirect: (context, state) =>
            PdfTool.byId(state.pathParameters['toolId']) == null
            ? AppRoutes.tools
            : null,
        builder: (context, state) =>
            PdfToolScreen(tool: PdfTool.byId(state.pathParameters['toolId'])!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);
