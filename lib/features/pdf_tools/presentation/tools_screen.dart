import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.toolsTitle)),
      body: ListView.separated(
        itemCount: PdfTool.values.length,
        separatorBuilder: (_, _) => const Divider(indent: 72),
        itemBuilder: (context, index) {
          final tool = PdfTool.values[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor: Theme.of(
                context,
              ).colorScheme.onSecondaryContainer,
              child: Icon(tool.icon, size: 20),
            ),
            title: Text(tool.title(l10n)),
            subtitle: Text(tool.hint(l10n)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.pdfTool(tool.id)),
          );
        },
      ),
    );
  }
}
