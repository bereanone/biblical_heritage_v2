/// Closing punctuation belongs to the preceding word; opening punctuation
/// belongs to the following word. A fitting font must keep those units intact.
bool presentationBreakOrphansPunctuation(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return false;
  const closing = ',.;:!?%)]}»”’、。，；：！？';
  const opening = '([{«“‘';
  return closing.contains(text[offset]) || opening.contains(text[offset - 1]);
}
