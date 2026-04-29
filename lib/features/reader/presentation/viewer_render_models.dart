import 'viewer_passage_models.dart';

sealed class ViewerRenderItem {
  const ViewerRenderItem();
}

class ViewerAcrosticItem extends ViewerRenderItem {
  const ViewerAcrosticItem({
    required this.blockId,
    required this.hebrew,
    required this.transliteration,
  });

  final int blockId;
  final String hebrew;
  final String transliteration;
}

class ViewerHeadingItem extends ViewerRenderItem {
  const ViewerHeadingItem({
    required this.blockId,
    required this.text,
  });

  final int blockId;
  final String text;
}

class ViewerVerseItem extends ViewerRenderItem {
  const ViewerVerseItem({
    required this.line,
  });

  final VerseLine line;
}
