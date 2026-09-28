import 'dart:io';

import '../../../core/theme/app_settings_service.dart';

enum BibleLoopUnit { book, chapter, verse }

class BibleLoopAnnouncementSettings {
  const BibleLoopAnnouncementSettings({
    this.book = false,
    this.chapter = false,
    this.verse = false,
  });

  final bool book;
  final bool chapter;
  final bool verse;

  bool enabledFor(BibleLoopUnit unit) => switch (unit) {
    BibleLoopUnit.book => book,
    BibleLoopUnit.chapter => chapter,
    BibleLoopUnit.verse => verse,
  };

  BibleLoopAnnouncementSettings withValue(BibleLoopUnit unit, bool value) =>
      BibleLoopAnnouncementSettings(
        book: unit == BibleLoopUnit.book ? value : book,
        chapter: unit == BibleLoopUnit.chapter ? value : chapter,
        verse: unit == BibleLoopUnit.verse ? value : verse,
      );

  String? cueAssetFor(
    BibleLoopUnit unit, {
    required int bookNumber,
    required int chapterNumber,
    required int verseNumber,
  }) {
    if (!enabledFor(unit)) return null;
    final root = Platform.isAndroid
        ? 'assets/audio/qwen_loop_cues_android'
        : 'assets/audio/qwen_loop_cues';
    return switch (unit) {
      BibleLoopUnit.book when bookNumber >= 1 && bookNumber <= 66 =>
        '$root/book_${bookNumber.toString().padLeft(2, '0')}.m4a',
      BibleLoopUnit.chapter when chapterNumber >= 1 && chapterNumber <= 150 =>
        '$root/chapter_${chapterNumber.toString().padLeft(3, '0')}.m4a',
      BibleLoopUnit.verse when verseNumber >= 1 && verseNumber <= 176 =>
        '$root/verse_${verseNumber.toString().padLeft(3, '0')}.m4a',
      _ => null,
    };
  }

  String? cueFor(
    BibleLoopUnit unit, {
    required String bookName,
    required int chapterNumber,
    required int verseNumber,
  }) {
    if (!enabledFor(unit)) return null;
    return switch (unit) {
      BibleLoopUnit.book => bookName.trim().isEmpty ? null : bookName.trim(),
      BibleLoopUnit.chapter => 'Chapter ${_spokenNumber(chapterNumber)}',
      BibleLoopUnit.verse => 'Verse ${_spokenNumber(verseNumber)}',
    };
  }
}

String _spokenNumber(int value) {
  if (value < 0 || value > 999) return value.toString();
  const belowTwenty = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];
  if (value < 20) return belowTwenty[value];
  if (value < 100) {
    final remainder = value % 10;
    return remainder == 0
        ? tens[value ~/ 10]
        : '${tens[value ~/ 10]} ${belowTwenty[remainder]}';
  }
  final remainder = value % 100;
  final hundred = '${belowTwenty[value ~/ 100]} hundred';
  return remainder == 0 ? hundred : '$hundred ${_spokenNumber(remainder)}';
}

class BibleLoopAnnouncementSettingsStore {
  const BibleLoopAnnouncementSettingsStore({this.loadValue, this.saveValue});

  final Future<String?> Function(String key)? loadValue;
  final Future<void> Function(String key, String value)? saveValue;

  static const _bookKey = 'bible_loop.announce_book_v1';
  static const _chapterKey = 'bible_loop.announce_chapter_v1';
  static const _verseKey = 'bible_loop.announce_verse_v1';

  String _keyFor(BibleLoopUnit unit) => switch (unit) {
    BibleLoopUnit.book => _bookKey,
    BibleLoopUnit.chapter => _chapterKey,
    BibleLoopUnit.verse => _verseKey,
  };

  Future<BibleLoopAnnouncementSettings> load() async {
    final load = loadValue ?? AppSettingsService.instance.loadRawSetting;
    final values = await Future.wait([
      load(_bookKey),
      load(_chapterKey),
      load(_verseKey),
    ]);
    return BibleLoopAnnouncementSettings(
      book: values[0] == '1',
      chapter: values[1] == '1',
      verse: values[2] == '1',
    );
  }

  Future<void> save(BibleLoopUnit unit, bool enabled) {
    final write = saveValue ?? AppSettingsService.instance.saveRawSetting;
    return write(_keyFor(unit), enabled ? '1' : '0');
  }
}
