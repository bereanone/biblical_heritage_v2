import 'package:flutter/services.dart';

/// Copy the captured selection shown by the action menu. Do not reload whole
/// verses or consult a selection that may have changed while the menu was open.
Future<void> copyViewerSelectionToClipboard({
  required String selectedText,
  required String citation,
  required bool includeCitation,
}) => Clipboard.setData(
  ClipboardData(
    text: includeCitation ? '$selectedText\n$citation' : selectedText,
  ),
);
