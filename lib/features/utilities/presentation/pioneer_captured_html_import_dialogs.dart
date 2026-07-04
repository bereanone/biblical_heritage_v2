import 'package:flutter/material.dart';

import '../data/pioneer_captured_html_import_folder_service.dart';

enum PioneerCaptureImportOfferAction { importAll, chooseSpecific, notNow }

Future<PioneerCaptureImportOfferAction?> showCaptureClipperImportOfferDialog(
  BuildContext context,
  PioneerCapturedHtmlAvailableImportReport report,
) {
  final imports = report.imports;
  if (imports.isEmpty) return Future<PioneerCaptureImportOfferAction?>.value();

  if (imports.length == 1) {
    final import = imports.single;
    return showDialog<PioneerCaptureImportOfferAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('CaptureClipper import ready'),
        content: Text(
          '1 CaptureClipper book is ready to import:\n\n${import.displayLabel}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(PioneerCaptureImportOfferAction.notNow),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(PioneerCaptureImportOfferAction.importAll),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  return showDialog<PioneerCaptureImportOfferAction>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('CaptureClipper imports ready'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          child: Text(
            '${imports.length} CaptureClipper books are ready to import.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(PioneerCaptureImportOfferAction.notNow),
          child: const Text('Not Now'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(PioneerCaptureImportOfferAction.chooseSpecific),
          child: const Text('Choose...'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(PioneerCaptureImportOfferAction.importAll),
          child: const Text('Import'),
        ),
      ],
    ),
  );
}

Future<List<PioneerCapturedHtmlAvailableImport>?>
showCaptureClipperImportChooserDialog(
  BuildContext context,
  PioneerCapturedHtmlAvailableImportReport report,
) {
  final imports = report.imports;
  if (imports.isEmpty) {
    return Future<List<PioneerCapturedHtmlAvailableImport>?>.value();
  }
  if (imports.length == 1) {
    final import = imports.single;
    return showDialog<List<PioneerCapturedHtmlAvailableImport>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import CaptureClipper book?'),
        content: Text(import.displayLabel),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(<PioneerCapturedHtmlAvailableImport>[import]),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  return showDialog<List<PioneerCapturedHtmlAvailableImport>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final selected = <String, bool>{
        for (final item in imports) item.folderPath: true,
      };
      return StatefulBuilder(
        builder: (context, setState) {
          final selectedCount = selected.values.where((value) => value).length;
          return AlertDialog(
            title: const Text('Choose books to import'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$selectedCount of ${imports.length} selected.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: imports.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        final import = imports[index];
                        return CheckboxListTile(
                          value: selected[import.folderPath] ?? false,
                          onChanged: (value) {
                            setState(() {
                              selected[import.folderPath] = value ?? false;
                            });
                          },
                          title: Text(import.displayLabel),
                          subtitle: Text(import.author),
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Not Now'),
              ),
              FilledButton(
                onPressed: selectedCount == 0
                    ? null
                    : () {
                        final selectedImports = imports
                            .where(
                              (import) => selected[import.folderPath] == true,
                            )
                            .toList(growable: false);
                        Navigator.of(dialogContext).pop(selectedImports);
                      },
                child: const Text('Import'),
              ),
            ],
          );
        },
      );
    },
  );
}
