/// Move an old audio time to the same source word in a corrected recording.
/// Unknown versions and books without an explicit map are left untouched.
Map<String, dynamic> remapLibraryAudioPosition(
  Map<String, dynamic> saved,
  Map<String, dynamic>? migration,
  List<dynamic>? currentTracks,
) {
  if (migration == null || currentTracks == null) return saved;
  final target = migration['to'];
  final version = saved['timeline_version'] ?? '';
  if (target is! String ||
      version == target ||
      !(migration['from_versions'] as List? ?? const []).contains(version))
    return saved;
  final chapter = saved['chapter'];
  final position = saved['position_ms'];
  if (position is! num || chapter is! num) return saved;
  Map? previousTrack, currentTrack;
  for (final t in migration['tracks'] as List? ?? const []) {
    if (t['chapter'] == chapter) previousTrack = t as Map;
  }
  for (final t in currentTracks) {
    if (t['chapter'] == chapter) currentTrack = t as Map;
  }
  if (previousTrack == null || currentTrack == null) return saved;
  Map? previousCue;
  for (final c in previousTrack['cues'] as List? ?? const []) {
    if ((c['start_ms'] as num) <= position) previousCue = c as Map;
  }
  var mapped = 0;
  if (previousCue != null) {
    Map? currentCue;
    for (final c in currentTrack['cues'] as List? ?? const []) {
      if (c['source_cursor'].toString() ==
          previousCue['source_cursor'].toString())
        currentCue = c as Map;
    }
    if (currentCue == null) return saved;
    var offset = 0;
    final elapsed = position - (previousCue['start_ms'] as num);
    for (final w in previousCue['words'] as List? ?? const []) {
      if ((w[0] as num) <= elapsed) offset = (w[1] as num).toInt();
    }
    num relative = 0;
    var nearestOffset = -1;
    for (final w in currentCue['phrases'] as List? ?? const []) {
      final candidate = w['source_start_offset'] as num?;
      if (candidate != null &&
          candidate <= offset &&
          candidate >= nearestOffset) {
        nearestOffset = candidate.toInt();
        relative = w['start_ms'] as num;
      }
    }
    mapped = ((currentCue['start_ms'] as num) + relative).round();
  }
  return {...saved, 'position_ms': mapped, 'timeline_version': target};
}
