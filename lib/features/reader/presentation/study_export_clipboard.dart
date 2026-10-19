import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/presentation/presentation_text_format.dart';

String studyExportHtml(String text, {String? formatJson}) {
  return buildPresentationTextSpans(text: text, baseStyle: const TextStyle(), formatJson: formatJson).cast<TextSpan>().map((span) {
    var html = const HtmlEscape().convert(span.text ?? '').replaceAll('\n', '<br>');
    final style = span.style;
    if (style?.fontWeight == FontWeight.w700) html = '<b>$html</b>';
    if (style?.fontStyle == FontStyle.italic) html = '<i>$html</i>';
    if (style?.decoration?.contains(TextDecoration.underline) == true) html = '<u>$html</u>';
    return html;
  }).join();
}

Future<void> copyStudyExport({required String text, required String html}) async {
  try {
    await const MethodChannel('studybible/rich_clipboard').invokeMethod<void>('write', {'text': text, 'html': '<html><body>$html</body></html>'});
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
