/// What a spoken clip contains. References and titles live inside clips of
/// the entry they introduce; the kind only drives diagnostics and tests.
/// [passage] is the quoted text of a non-scripture entry (an eLibrary quote).
enum TagClipKind { verse, passage, note }

/// One unit of synthesis: a single text string that becomes one audio file.
class TagSpeechClip {
  const TagSpeechClip({
    required String text,
    required this.kind,
    this.blockId,
    this.reference,
    this.sourceBody,
    this.sourceReference,
  }) : body = text;

  /// The words of the clip without its reference lead-in.
  final String body;

  // Preserve the unedited verse and lead-in after resolving playback settings.
  final String? sourceBody;
  final String? sourceReference;

  final TagClipKind kind;

  /// Spoken identifier ("John 3, verse 16", "Steps to Christ, page 12,
  /// paragraph 3", a note's own title) that leads the clip, kept apart from
  /// [body] so it can be dropped without an empty or awkward clip. Null when
  /// the clip has no reference.
  final String? reference;

  /// Bible block id of the verse this clip ends with, when the body is exactly
  /// that verse. The pronunciation layer uses it to apply the verse's KJV
  /// patches, which is why the reference is never merged into [body]. Always
  /// null for notes.
  final int? blockId;

  /// The clip as spoken with the reference on.
  String get text {
    final lead = reference;
    if (lead == null) return body;
    return body.isEmpty ? '$lead.' : '$lead. $body';
  }

  /// The clip to synthesize for the chosen mode, or null when nothing is left
  /// to say (a reference-only clip with the reference off). The result has no
  /// separate reference, so its [text] is exactly what is spoken.
  TagSpeechClip? resolved({required bool speakReference}) {
    if (reference == null) return body.trim().isEmpty ? null : this;
    if (speakReference) {
      return TagSpeechClip(
        text: text,
        kind: kind,
        blockId: blockId,
        sourceBody: body,
        sourceReference: reference,
      );
    }
    if (body.trim().isEmpty) return null;
    return TagSpeechClip(
      text: body,
      kind: kind,
      blockId: blockId,
      sourceBody: body,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TagSpeechClip &&
      other.body == body &&
      other.reference == reference &&
      other.kind == kind &&
      other.blockId == blockId &&
      other.sourceBody == sourceBody &&
      other.sourceReference == sourceReference;

  @override
  int get hashCode =>
      Object.hash(body, reference, kind, blockId, sourceBody, sourceReference);

  @override
  String toString() => 'TagSpeechClip(${kind.name}, $blockId, $text)';
}

/// One entry of a tag, prepared for speech.
class TagPlaybackItem {
  const TagPlaybackItem({
    required this.entryId,
    required this.label,
    required this.preview,
    this.contentClips = const <TagSpeechClip>[],
    this.noteClips = const <TagSpeechClip>[],
  });

  final int entryId;

  /// Reference (or title) shown while this entry is current.
  final String label;

  /// One-line excerpt for the list.
  final String preview;

  /// The entry's identifier plus its own content (verse text, an eLibrary
  /// quote). A note-only entry has no content, so this is just its identifier
  /// (or empty when it has none).
  final List<TagSpeechClip> contentClips;

  /// Attached note text (chunked). Empty when the entry has no note.
  final List<TagSpeechClip> noteClips;

  bool get hasNote => noteClips.isNotEmpty;

  /// The clips to speak, in order. Entries with nothing to say in the chosen
  /// mode return an empty list and are skipped by the controller.
  List<TagSpeechClip> clipsFor({
    required bool includeNotes,
    bool speakReference = true,
  }) => [
    for (final clip in [...contentClips, if (includeNotes) ...noteClips])
      ?clip.resolved(speakReference: speakReference),
  ];
}

enum TagPlaybackStatus {
  /// Nothing started yet, or stopped.
  idle,

  /// Playback requested; waiting for the next clip to be synthesized.
  loading,
  playing,
  paused,

  /// A single pass reached the end (loop off).
  finished,
  error,
}
