import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_text_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/study_export_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('HTML escapes content and retains all three note decorations', () {
    expect(studyExportHtml('bold & <x>', formatJson: jsonEncode({'base_text_hash': presentationTextFormatHashForText('bold & <x>'), 'spans': [{'start': 0, 'end': 4, 'bold': true, 'italic': true, 'underline': true}]})), '<u><i><b>bold</b></i></u> &amp; &lt;x&gt;');
    expect(studyExportHtml('one\ntwo'), 'one<br>two');
  });
  test('clipboard writes rich and plain representations together', () async {
    MethodCall? captured;
    const channel = MethodChannel('studybible/rich_clipboard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { captured = call; return null; });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await copyStudyExport(text: 'bold', html: '<b>bold</b>');
    expect(captured?.method, 'write');
    expect(captured?.arguments, {'text': 'bold', 'html': '<html><body><b>bold</b></body></html>'});
  });
}
