import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/note_image_clipboard.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('studybible/rich_clipboard');
  final bytes=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1cAAAAASUVORK5CYII=');
  tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null));
  test('image clipboard transports actual bytes and does not change the source',()async{
    final original=List<int>.of(bytes);Uint8List? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call)async{
      if(call.method=='writeImage'){copied=(call.arguments as Map)['bytes'] as Uint8List;expect((call.arguments as Map)['mimeType'],'image/png');return null;}
      if(call.method=='readImage')return copied;
      throw MissingPluginException();
    });
    await NoteImageClipboard.copy(bytes,'image/png');
    expect(await NoteImageClipboard.read(),original);expect(bytes,original);
  });
  test('copy failure is surfaced instead of pretending to succeed',()async{
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call)async=>throw PlatformException(code:'clipboard_failed'));
    await expectLater(NoteImageClipboard.copy(bytes,'image/png'),throwsA(isA<PlatformException>()));
  });
  testWidgets('long press offers copy without removing original attachment',(tester)async{
    var copies=0,removals=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:NoteImageThumbnail(bytes:bytes,onCopy:()=>copies++,onRemove:()=>removals++)))));
    await tester.longPress(find.byType(NoteImageThumbnail));await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Image'));await tester.pumpAndSettle();
    expect(copies,1);expect(removals,0);expect(find.byType(NoteImageThumbnail),findsOneWidget);
  });
}
