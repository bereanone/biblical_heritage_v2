import 'dart:convert';

import 'memory_schedule/memory_schedule.dart';
import 'memory_schedule/memory_schedule_editor.dart';
import 'memory_schedule/memory_schedule_reminder.dart';

import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/theme/app_settings_service.dart';
import '../data/bible_memory_repository.dart';
import 'bible_memory_support.dart';
import 'tag_dialog_styles.dart';
import 'tag_playback/tag_playback_models.dart';
import 'tag_playback/tag_playback_popup.dart';
import 'tag_playback/tag_playback_session.dart';
import 'tag_playback/tag_playback_settings.dart';

Future<void> showMemoryAudioPopup(
  BuildContext context,
  MemoryVerse passage, {
  bool autoStart = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final size = TagDialogStyles.detailModalSize(MediaQuery.sizeOf(context));
      return Dialog(
        insetPadding: TagDialogStyles.outerInset,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: TagPlaybackDialog(
            tag: passage.reference,
            autoStart: autoStart,
            onSchedule: () {
              final target = MemoryAudioTarget(
                label: passage.reference,
                memoryId: passage.id,
              );
              return showMemoryScheduleEditor(
                context,
                target,
                preview: () => showMemoryAudioReminder(context, target),
              );
            },
            open: () => openMemoryAudioSession(passage),
          ),
        ),
      );
    },
  );
}

Future<TagPlaybackSession> openMemoryAudioSession(MemoryVerse passage) async {
  final rows = await BibleMemorySupport.loadVerseRowsInRange(
    bookNumber: passage.bookNumber,
    startChapter: passage.chapter,
    startVerse: passage.verse,
    endChapter: passage.endChapter,
    endVerse: passage.endVerse,
  );
  if (rows.isEmpty) throw StateError('No audio text found for this passage.');
  final items = <TagPlaybackItem>[];
  for (final row in rows) {
    final chapter = (row['chapter'] as num).toInt();
    final verse = (row['verse'] as num).toInt();
    final text = row['text'] as String;
    final block = await StudyBibleDatabase.instance.loadBlockIdForVerse(
      bookNumber: passage.bookNumber,
      chapter: chapter,
      verse: verse,
    );
    items.add(
      TagPlaybackItem(
        entryId: block ?? items.length,
        label: '${passage.bookName} $chapter:$verse',
        preview: text,
        contentClips: [
          TagSpeechClip(
            text: text,
            kind: TagClipKind.verse,
            blockId: block,
            reference: '${passage.bookName} $chapter, verse $verse',
          ),
        ],
      ),
    );
  }
  return TagPlaybackSession.openItems(
    tag: passage.reference,
    items: items,
    settingsStore: _MemoryAudioSettingsStore(passage.id),
  );
}

/// Each memory entry remembers its own choices without changing hashtag audio.
class _MemoryAudioSettingsStore implements TagPlaybackSettingsStore {
  _MemoryAudioSettingsStore(this.id);
  final int id;
  String get _key => 'memory_audio.settings.$id';

  @override
  Future<TagPlaybackSettings> load() async {
    final raw = await AppSettingsService.instance.loadRawSetting(_key);
    if (raw == null) {
      return const TagPlaybackSettings(
        speakNotes: false,
        speakReference: false,
      );
    }
    final value = jsonDecode(raw) as Map<String, dynamic>;
    return TagPlaybackSettings(
      speakNotes: false,
      speakReference: value['reference'] == true,
      loop: value['loop'] == true,
    );
  }

  @override
  Future<void> save(TagPlaybackSettings settings) {
    return AppSettingsService.instance.saveRawSetting(
      _key,
      jsonEncode({'reference': settings.speakReference, 'loop': settings.loop}),
    );
  }
}
