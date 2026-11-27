import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/shell/app_shell.dart';
import 'package:md_scanner/features/document_scanner/presentation/scan_review_screen.dart';
import 'package:md_scanner/features/document_scanner/presentation/scanner_screen.dart';
import 'package:md_scanner/features/document_vault/presentation/document_details_screen.dart';
import 'package:md_scanner/features/document_vault/presentation/documents_screen.dart';
import 'package:md_scanner/features/document_vault/presentation/trash_screen.dart';
import 'package:md_scanner/features/home/presentation/home_screen.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool_screen.dart';
import 'package:md_scanner/features/pdf_tools/presentation/tools_screen.dart';
import 'package:md_scanner/features/settings/presentation/profile_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
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
