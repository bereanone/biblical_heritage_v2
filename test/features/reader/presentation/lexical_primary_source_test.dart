import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_repository.dart';
ViewerStrongsEntry entry(String id, String pos) => ViewerStrongsEntry(strongsId: id, language: 'G', lemma: '', transliteration: '', pronunciation: '', partOfSpeech: pos, shortDefinition: '');
void main() {
  test('shadow noun opens directly over article in either mapping order', () {
    final noun = entry('G4639', 'noun'); final article = entry('G3588', 'definite article');
    expect(selectPrimaryStrongsSource([article, noun]), 'G4639');
    expect(selectPrimaryStrongsSource([noun, article]), 'G4639');
  });
  test('ambiguous, missing and grammar-only mappings retain chooser', () {
    final noun = entry('G4639', 'noun');
    expect(selectPrimaryStrongsSource([noun, entry('G0001', 'verb')]), isNull);
    expect(selectPrimaryStrongsSource([noun, null]), isNull);
    expect(selectPrimaryStrongsSource([entry('G3588', 'definite article')]), isNull);
  });
}
