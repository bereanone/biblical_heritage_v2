import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_selection_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  test(
    'single word without citation writes only that word to clipboard',
    () async {
      await copyViewerSelectionToClipboard(
        selectedText: 'God',
        citation: 'Genesis 1:1',
        includeCitation: false,
      );
      expect(clipboard, 'God');
    },
  );
  test('single word with citation keeps word selection', () async {
    await copyViewerSelectionToClipboard(
      selectedText: 'God',
      citation: 'Genesis 1:1',
      includeCitation: true,
    );
    expect(clipboard, 'God\nGenesis 1:1');
  });
  test('multi-word and whole-verse selections retain captured text', () async {
    for (final selected in [
      'the heaven and the earth.',
      'In the beginning God created the heaven and the earth.',
    ]) {
      await copyViewerSelectionToClipboard(
        selectedText: selected,
        citation: 'Genesis 1:1',
        includeCitation: false,
      );
      expect(clipboard, selected);
    }
  });
}
