import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/watch_library_playback.dart';
import 'package:studybible2/features/library/presentation/watch_library_reader_coordinator.dart';

WatchLibraryPlayback state(String book, {int seconds = 0}) =>
    WatchLibraryPlayback(
      bookId: book,
      chapter: 1,
      paragraph: 1,
      position: Duration(seconds: seconds),
      playing: true,
      nativePlayback: true,
      loop: 'chapter',
    );
void main() {
  testWidgets(
    'Watch book changes replace the current book; progress does not open duplicate readers',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final playback = ValueNotifier<WatchLibraryPlayback?>(null);
      final currentReader = Object();
      final opened = <String>[], fallback = <String>[];
      WatchLibraryReaderNavigation.register(currentReader, (book) async {
        opened.add(book);
        return true;
      });
      final coordinator = WatchLibraryReaderCoordinator(
        playback: playback,
        openBook: (book) async {
          fallback.add(book);
        },
      )..start();
      await tester.pumpWidget(const SizedBox.shrink());
      playback.value = state('lof');
      await tester.pump();
      await tester.pump();
      playback.value = state('wor');
      await tester.pump();
      await tester.pump();
      for (var i = 1; i <= 100; i++) {
        playback.value = state('wor', seconds: i);
      }
      await tester.pump();
      expect(opened, ['lof', 'wor']);
      expect(fallback, isEmpty);
      WatchLibraryReaderNavigation.unregister(currentReader);
      playback.value = state('sdp');
      await tester.pump();
      await tester.pump();
      expect(fallback, ['sdp']);
      coordinator.dispose();
      playback.dispose();
    },
  );
  testWidgets(
    'background selection opens the latest book on return to the phone',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final playback = ValueNotifier<WatchLibraryPlayback?>(null);
      final opened = <String>[];
      final coordinator = WatchLibraryReaderCoordinator(
        playback: playback,
        openBook: (book) async {
          opened.add(book);
        },
      )..start();
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      playback.value = state('lof');
      playback.value = state('wor');
      await tester.pump();
      expect(opened, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(opened, ['wor']);
      coordinator.dispose();
      playback.dispose();
    },
  );
}
