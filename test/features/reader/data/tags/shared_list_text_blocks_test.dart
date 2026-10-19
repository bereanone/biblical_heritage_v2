import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/tags/shared_list_text_blocks.dart';
List<List<String>> parse(String text)=>splitSharedListTextBlocks(text.split('\n'),
  isWrapper:(s)=>s.startsWith('Shared from'),
  isListHeader:(s)=>s.startsWith('#Sabbath ('),
  isSlideStart:(s)=>RegExp(r'^Exodus \d+:').hasMatch(s));
void main() {
  test('edited export produces four cards, ignoring instructions and retaining note paragraphs',(){
    final blocks=parse('Shared from the Biblical Heritage #StudyBible app.\n\nFor instructions on using the app, visit BiblicalHeritage.net.\n\n#Sabbath (2 items)\n\nExodus 20:8-11\n8 Remember the sabbath day.\n\nSabbath Note 1\n[Image: Sabbath Note 1 image]\nOriginal note.\n\nExodus 20:8-10\n8 Remember the sabbath day.\n\nSabbath Note 2\n\nThis is new.\n\nSecond paragraph.');
    expect(blocks.length,4);
    expect(blocks.map((b)=>b.first),['Exodus 20:8-11','Sabbath Note 1','Exodus 20:8-10','Sabbath Note 2']);
    expect(blocks.last.join('\n'),'Sabbath Note 2\n\nThis is new.\n\nSecond paragraph.');
  });
  test('instruction quotation inside a real note is preserved',(){
    final blocks=parse('#Sabbath (1 item)\n\nSabbath Note 1\nFor instructions on using the app, visit BiblicalHeritage.net.');
    expect(blocks.single.length,2);
  });
  test('legacy unlabelled blank-separated cards remain distinct',(){
    expect(parse('Quotation one\nIts body\n\nQuotation two\nIts body').length,2);
  });
  test('optional header and footer remain inside their note, never extra cards',(){
    final blocks=parse('#Sabbath (2 items)\n\nSabbath Note 1\n\nHeader: My header\n\nFirst note body.\n\nFooter: My footer\n\nSabbath Note 2\n\nSecond note without header or footer.');
    expect(blocks.length,2);
    expect(blocks.first.join('\n'),contains('Header: My header'));
    expect(blocks.first.join('\n'),contains('Footer: My footer'));
    expect(blocks.last.first,'Sabbath Note 2');
  });
  test('multiple paragraph breaks and wrapper quotations stay inside explicit note',(){
    final text='Sabbath Note 1\n\n\nFor instructions on using the app, visit BiblicalHeritage.net.\nShared from the Biblical Heritage #StudyBible app.\n\n\nEnd.';
    expect(parse(text).single.join('\n'),text);
  });
}
