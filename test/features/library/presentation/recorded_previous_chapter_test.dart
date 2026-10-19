import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
void main() {
 test('previous restarts chapter one midway', () { expect(previousRecordedChapterIndex(0, const Duration(seconds: 45)), 0); });
 test('previous restarts another chapter midway', () { expect(previousRecordedChapterIndex(4, const Duration(seconds: 45)), 4); });
 test('previous near the start goes to preceding chapter', () { expect(previousRecordedChapterIndex(4, const Duration(seconds: 1)), 3); });
 test('previous never goes before chapter one', () { expect(previousRecordedChapterIndex(0, Duration.zero), 0); });
}
