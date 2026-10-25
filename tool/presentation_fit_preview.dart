import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:studybible2/features/reader/data/presentation/note_image_layout.dart';
import 'package:studybible2/features/reader/presentation/note_image_layout_editor.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_models.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_slide_settings.dart';
import 'package:studybible2/features/reader/presentation/presentation_slide_canvas.dart';
import 'package:studybible2/features/reader/presentation/viewer_presentation_settings.dart';

const sabbath =
    '8 Remember the sabbath day, to keep it holy.\n'
    '9 Six days shalt thou labour, and do all thy work:\n'
    '10 But the seventh day is the sabbath of the LORD thy God: in it thou shalt not do any work, '
    'thou, nor thy son, nor thy daughter, thy manservant, nor thy maidservant, nor thy cattle, '
    'nor thy stranger that is within thy gates:\n'
    '11 For in six days the LORD made heaven and earth, the sea, and all that in them is, '
    'and rested the seventh day: wherefore the LORD blessed the sabbath day, and hallowed it.';
void main() =>
    runApp(MaterialApp(theme: ThemeData.dark(), home: const Review()));

class Review extends StatefulWidget {
  const Review({super.key});
  @override
  State<Review> createState() => _ReviewState();
}

class _ReviewState extends State<Review> {
  int example = 0;
  bool phone = false;
  NoteImageLayout imageLayout = const NoteImageLayout(
    rows: 4,
    columns: 4,
    row: 0,
    column: 2,
    rowSpan: 2,
    columnSpan: 2,
    fill: false,
    footer: 'Exodus 20:8-11',
  );
  String? illustration;
  PresentationBlockAlignments imageAlignments =
      const PresentationBlockAlignments(footer: TextAlign.right);
  @override
  void initState() {
    super.initState();
    prepareImage();
  }

  Future<void> prepareImage() async {
    final data = await rootBundle.load(
      'assets/bundled_library/files/33fff50aab49ef3dfdf89fa5bc72ff29ef7a113e508daf22fb3285c5850078bd',
    );
    final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());
    final bytes = archive
        .findFile('OPS/images/approved/frontispiece.png')!
        .content;
    final folder = await getTemporaryDirectory();
    final image = File('${folder.path}/presentation-review-illustration.png');
    await image.writeAsBytes(bytes);
    if (mounted) setState(() => illustration = image.path);
  }

  Future<void> chooseImageSquares() async {
    final image = await File(illustration!).readAsBytes();
    if (!mounted) return;
    final result = await showNoteImageLayoutEditor(
      context,
      images: [image],
      text: sabbath,
      formatJson: imageAlignments.withFormat(null),
      initial: imageLayout,
    );
    if (!mounted || result?.layout == null) return;
    setState(() {
      imageLayout = result!.layout!;
      imageAlignments = result.alignments ?? imageAlignments;
    });
  }

  @override
  Widget build(BuildContext context) {
    final slide = PresentationSlide(
      id: 'review',
      settingsKey: 'review',
      slideNumber: 1,
      layoutType: PresentationLayoutType.fullWidth,
      items: [
        PresentationSlideItem(
          id: 'passage',
          presentationSlideId: 'review',
          sourceType: 'bible',
          sourceId: '1',
          bookNumber: 2,
          chapter: 20,
          verse: 8,
          verseEnd: 11,
          layoutRegion: PresentationLayoutRegion.full,
          layoutOrder: 0,
          itemKind: example == 2
              ? PresentationItemKind.note
              : PresentationItemKind.verse,
          displayTitle: '',
          displayText: example == 1
              ? List.filled(8, sabbath).join('\n')
              : example == 2
              ? sabbath
              : sabbath,
          noteFormatJson: example == 2
              ? imageAlignments.withFormat(
                  noteFormatWithImageLayout(null, imageLayout),
                )
              : null,
          mediaRefs: example == 2 ? [illustration!] : null,
        ),
      ],
    );
    Widget canvas = PresentationSlideCanvas(
      slide: slide,
      aspectRatioPreset: phone
          ? PresentationAspectRatioPreset.auto
          : PresentationAspectRatioPreset.sixteenByNine,
      bookNames: const {2: 'Exodus'},
      settings: const PresentationSlideSettings(),
      mediaRootPaths: const [],
    );
    if (phone) {
      canvas = Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: 390, height: 700, child: canvas),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Presentation fix — review only')),
      body: Column(
        children: [
          Wrap(
            spacing: 12,
            children: [
              for (final pair in [
                (0, 'Sabbath passage'),
                (1, 'Overflow example'),
                (2, 'Image area'),
              ])
                TextButton(
                  onPressed: pair.$1 == 2 && illustration == null
                      ? null
                      : () => setState(() => example = pair.$1),
                  child: Text(pair.$2),
                ),
              if (example == 2)
                TextButton(
                  onPressed: chooseImageSquares,
                  child: const Text('Choose image squares'),
                ),
              TextButton(
                onPressed: () => setState(() => phone = !phone),
                child: Text(phone ? 'Show Mac size' : 'Show phone size'),
              ),
            ],
          ),
          Expanded(child: canvas),
        ],
      ),
    );
  }
}
