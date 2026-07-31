import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/pioneer_ellenwhite_audio_service.dart';

const String _fixtureHtml = '''
<html>
  <body>
    <h2>Uriah Smith</h2>
    <div class="book">
      <a href="/covers/daniel-revelation.jpg"><img src="/covers/daniel-revelation.jpg" alt="Daniel and the Revelation"></a>
      Daniel and the Revelation
      <a href="/ebooks/en/smith/Daniel%20and%20the%20Revelation.pdf">PDF</a>
      <a href="https://ellenwhiteaudio.org/ebooks/en/smith/Daniel%20and%20the%20Revelation.epub">EPUB</a>
      <a href="/ebooks/en/smith/Daniel%20and%20the%20Revelation.mobi">MOBI</a>
    </div>
    <div class="book">
      <a href="/covers/home-here.jpg"><img src="/covers/home-here.jpg" alt="Home Here, and Home in Heaven; With Other Poems"></a>
      Home Here, and Home in Heaven; With Other Poems
      <a href="/ebooks/en/smith/Home%20Here%2C%20and%20Home%20in%20Heaven%3B%20With%20Other%20Poems.pdf">PDF</a>
      <a href="https://ellenwhiteaudio.org/ebooks/en/smith/Home%20Here%2C%20and%20Home%20in%20Heaven%3B%20With%20Other%20Poems.epub">EPUB</a>
      <a href="/ebooks/en/smith/Home%20Here%2C%20and%20Home%20in%20Heaven%3B%20With%20Other%20Poems.mobi">MOBI</a>
    </div>
    <h2>E. A. Sutherland</h2>
    <div class="book">
      <a href="/covers/living-fountains.jpg"><img src="/covers/living-fountains.jpg" alt="Living Fountains or Broken Cisterns"></a>
      Living Fountains or Broken Cisterns
      <a href="/ebooks/en/sutherland/Living%20Fountains%20or%20Broken%20Cisterns.pdf">PDF</a>
      <a href="/ebooks/en/sutherland/Living%20Fountains%20or%20Broken%20Cisterns.mobi">MOBI</a>
    </div>
  </body>
</html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'parses EllenWhiteAudio direct EPUB links from the pioneer page',
    () async {
      final service = PioneerEllenWhiteAudioService(
        fetcher: (uri) async {
          expect(
            uri.toString(),
            PioneerEllenWhiteAudioService.collectionPageUrl,
          );
          return _fixtureHtml;
        },
      );

      final catalog = await service.loadCatalog(refresh: true);
      final uriahSmith = catalog.authorById('uriah_smith');

      expect(catalog.authorCount, 2);
      expect(catalog.workCount, 3);
      expect(uriahSmith, isNotNull);
      expect(uriahSmith!.works.length, 2);

      final dar = catalog.workById('daniel_and_the_revelation');
      expect(dar, isNotNull);
      expect(dar!.title, 'Daniel and the Revelation');
      expect(dar.authorName, 'Uriah Smith');
      expect(dar.sourceType, 'directEpub');
      expect(dar.sourceTypeLabel, 'DIRECT EPUB');
      expect(dar.preferredImportCandidate, isNotNull);
      expect(dar.preferredImportCandidate!.sourceType, 'directEpub');
      expect(dar.isImportable, isTrue);

      final homeHere = catalog.workById(
        'home_here_and_home_in_heaven_with_other_poems',
      );
      expect(homeHere, isNotNull);
      expect(
        homeHere!.title,
        'Home Here, and Home in Heaven; With Other Poems',
      );
      expect(homeHere.isImportable, isTrue);

      final livingFountains = catalog.workById(
        'living_fountains_or_broken_cisterns',
      );
      expect(livingFountains, isNotNull);
      expect(livingFountains!.isImportable, isFalse);
      expect(livingFountains.hasDeferredPdfSource, isTrue);
    },
  );
}
