import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/slide_link_control.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';
import 'package:studybible2/features/reader/data/presentation/note_image_layout.dart';
void main(){
  test('Bible overlay save/readback retains link state and text formatting',(){
    var inner=jsonEncode({'spans':[{'start':0,'end':3,'bold':true}],'base_text_hash':'hash','image_layout':{'keep':true}});
    for(final linked in [true,false,true]){
      inner=presentationFormatWithLink(inner,linked);
      final stored=buildBibleItemOverlayJson(userTitle:'My title',displayTextOverride:'My passage',noteFormatJson:inner,titleFormatJson:'title-format',displayTextFormatJson:'verse-format');
      final reloaded=bibleItemOverlayNoteFormatJson(stored)!;
      expect(presentationLinksWithNext(reloaded),linked);
      expect(bibleItemOverlayUserTitle(stored),'My title');
      expect(bibleItemOverlayDisplayTextOverride(stored),'My passage');
      expect(bibleItemOverlayTitleFormatJson(stored),'title-format');
      expect(bibleItemOverlayDisplayTextFormatJson(stored),'verse-format');
      expect(jsonDecode(reloaded)['spans'],jsonDecode(inner)['spans']);
      expect(jsonDecode(reloaded)['image_layout'],{'keep':true});
      inner=reloaded;
    }
  });
  test('previously nested legacy overlays flatten without losing style or latest link',(){
    final original=jsonEncode({'spans':[{'start':0,'end':3,'bold':true}],'base_text_hash':'hash','link_with_next':true});
    final oldLayer=jsonDecode(buildBibleItemOverlayJson(noteFormatJson:original)!) as Map<String,dynamic>;
    oldLayer['link_with_next']=false;
    final stored=buildBibleItemOverlayJson(noteFormatJson:jsonEncode(oldLayer));
    final read=bibleItemOverlayNoteFormatJson(stored)!;
    final data=jsonDecode(read);
    expect(data['kind'],isNull);expect(data['spans'],jsonDecode(original)['spans']);
    expect(presentationLinksWithNext(read),false);
    expect(jsonDecode(presentationFormatWithLink(read,true))['kind'],isNull);
  });
  testWidgets('switch visibly changes OFF to ON and names linked entry',(tester)async{
    var linked=false;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,setState)=>SlideLinkControl(linked:linked,nextTitle:'Genesis 3:11',onChanged:(v)=>setState(()=>linked=v))))));
    expect(find.text('Link with next: OFF'),findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));await tester.pumpAndSettle();
    expect(find.text('Link with next: ON'),findsOneWidget);
    expect(find.text('Shares a slide with Genesis 3:11.'),findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));await tester.pumpAndSettle();
    expect(find.text('Link with next: OFF'),findsOneWidget);
  });
  testWidgets('disabled boundary explains why it cannot link',(tester)async{
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:SlideLinkControl(linked:false,onChanged:null,disabledReason:'Image notes use their own slide.'))));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNull);
    expect(find.text('Image notes use their own slide.'),findsOneWidget);
  });
  testWidgets('disabled link tap cannot activate the surrounding card',(tester)async{
    var opened=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:InkWell(onTap:()=>opened++,child:const SlideLinkControl(linked:false,onChanged:null,disabledReason:'Image notes use their own slide.')))));
    await tester.tap(find.text('Link with next: OFF'));await tester.pumpAndSettle();
    expect(opened,0);
    await tester.tap(find.byType(Switch));await tester.pumpAndSettle();
    expect(opened,0);
  });
}
