import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/note_image_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1cAAAAASUVORK5CYII=');
  test('selected screenshot is validated and original bytes are retained', () async {
    final before = List<int>.of(png);
    final result = await pickNoteImage(pick: () async => FilePickerResult([
      PlatformFile(name: 'Screenshot.png', size: png.length, bytes: png),
    ]));
    expect(result!.bytes, before); expect(png, before);
    expect(result.mimeType, 'image/png');
  });
  test('cancel is a no-op and unsupported content is rejected before staging', () async {
    expect(await pickNoteImage(pick: () async => null), isNull);
    await expectLater(pickNoteImage(pick: () async => FilePickerResult([
      PlatformFile(name: 'broken.png', size: 3, bytes: Uint8List.fromList([1,2,3])),
    ])), throwsA(anything));
  });
  testWidgets('paste feedback opens above editor and returns to the unchanged editor', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (pageContext) => TextButton(
      onPressed: () => showDialog<void>(context: pageContext, builder: (editorContext) => AlertDialog(
        title: const Text('Edit Bible range'),
        content: TextButton(onPressed: () => showNoteEditorFeedback(editorContext, 'Clipboard does not contain an image.'), child: const Text('Paste Image')),
      )), child: const Text('Edit'),
    )))));
    await tester.tap(find.text('Edit')); await tester.pumpAndSettle();
    await tester.tap(find.text('Paste Image')); await tester.pumpAndSettle();
    expect(find.text('Clipboard does not contain an image.').hitTestable(), findsOneWidget);
    expect(find.text('Paste Image').hitTestable(), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('OK')); await tester.pumpAndSettle();
    expect(find.text('Edit Bible range'), findsOneWidget);
    expect(find.text('Paste Image').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
