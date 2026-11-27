import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';

/// Bottom navigation with the five main entries. The Scanner entry sits in
/// the middle and is drawn as a filled accent button so it is found at once.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const int scannerIndex = 1;

  void _select(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _select,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: _ScannerIcon(
              color: scheme.secondary,
              onColor: scheme.onSecondary,
            ),
            selectedIcon: _ScannerIcon(
              color: scheme.secondary,
              onColor: scheme.onSecondary,
            ),
            label: l10n.navScanner,
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: l10n.navTools,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: l10n.navDocuments,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.navProfile,
          ),
        ],
      ),
    );
  }
}

class _ScannerIcon extends StatelessWidget {
  const _ScannerIcon({required this.color, required this.onColor});

  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.document_scanner_outlined, color: onColor, size: 20),
    );
  }
}
