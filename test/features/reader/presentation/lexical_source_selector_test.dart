import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_launcher.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_repository.dart';

class Sources extends ViewerStrongsRepository {
  @override
  Future<ViewerStrongsEntry?> loadEntry(String id) async => ViewerStrongsEntry(strongsId: id, language: 'G', lemma: id == 'G4639' ? 'shadow' : 'the', transliteration: '', pronunciation: '', partOfSpeech: id == 'G4639' ? 'noun' : 'definite article', shortDefinition: id == 'G4639' ? 'shade' : 'article');
  @override
  Future<int> loadOccurrenceCount(String id) async => 1;
  @override
  Future<ViewerAbbottSmithEntry?> loadAbbottSmithEntry(String id) async => null;
  @override
  Future<ViewerBdbEntry?> loadBdbEntry(String id) async => null;
}
void main() {
  testWidgets('primary source opens directly and alternate mapping remains reachable', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => showViewerStrongsPageOne(context, strongsId: 'G4639', alternateStrongsIds: const ['G3588', 'G4639'], onStrongsChanged: (id) => selected = id, onSelectBlockId: (_) {}, repository: Sources()), child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('shadow'), findsOneWidget);
    expect(find.textContaining('Sources for'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Source: G3588').last);
    await tester.pumpAndSettle();
    expect(selected, 'G3588');
    expect(find.text('the'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
