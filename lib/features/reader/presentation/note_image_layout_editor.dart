import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/presentation/note_image_layout.dart';
import 'note_image_flow.dart';

class NoteImageLayoutResult {
  const NoteImageLayoutResult(this.layout, [this.alignments]);
  final NoteImageLayout? layout;
  final PresentationBlockAlignments? alignments;
}

Future<NoteImageLayoutResult?> showNoteImageLayoutEditor(
  BuildContext context, {
  required List<Uint8List> images,
  required String text,
  required String? formatJson,
  NoteImageLayout? initial,
}) => showDialog<NoteImageLayoutResult>(
  context: context,
  builder: (_) => _ImageLayoutEditor(
    images: images,
    text: text,
    formatJson: formatJson,
    initial: initial,
  ),
);

class _ImageLayoutEditor extends StatefulWidget {
  const _ImageLayoutEditor({
    required this.images,
    required this.text,
    required this.formatJson,
    this.initial,
  });
  final List<Uint8List> images;
  final String text;
  final String? formatJson;
  final NoteImageLayout? initial;
  @override
  State<_ImageLayoutEditor> createState() => _ImageLayoutEditorState();
}

class _ImageLayoutEditorState extends State<_ImageLayoutEditor> {
  late int rows, columns, imageIndex;
  late Set<int> cells;
  late double ratio;
  late bool fill;
  late PresentationBlockAlignments alignments;
  late final TextEditingController header, footer;
  final _scrollController=ScrollController();
  @override
  void initState() {
    super.initState();
    alignments = PresentationBlockAlignments.fromFormat(widget.formatJson);
    final initial = widget.initial ?? const NoteImageLayout();
    rows = initial.rows;
    columns = initial.columns;
    cells = initial.cells;
    imageIndex = initial.imageIndex.clamp(
      0,
      math.max(0, widget.images.length - 1),
    );
    ratio = initial.aspectRatio;
    fill = initial.fill;
    header = TextEditingController(text: initial.header);
    footer = TextEditingController(text: initial.footer);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    header.dispose();
    footer.dispose();
    super.dispose();
  }

  NoteImageLayout? get selection => NoteImageLayout.fromCells(
    rows: rows,
    columns: columns,
    cells: cells,
    imageIndex: imageIndex,
    aspectRatio: ratio,
    fill: fill,
    header: header.text,
    footer: footer.text,
  );
  @override
  Widget build(BuildContext context) {
    final chosen = selection;
    final targets = <double, String>{
      16 / 9: '16:9 Widescreen',
      4 / 3: '4:3',
      16 / 10: '16:10',
      9 / 16: 'Phone portrait',
    };
    targets.putIfAbsent(ratio, () => 'Custom');
    return AlertDialog(
      title: const Text('Image Layout'),
      content: SizedBox(
        width: 880,
        height: math.min(680, MediaQuery.sizeOf(context).height * 0.70),
        child: SingleChildScrollView(
          controller:_scrollController,
          child: LayoutBuilder(
            builder: (context, c) {
              final panelWidth = math.min(390.0, c.maxWidth);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Display size comes from List settings for all slides. Tap cells to reserve one rectangular image area. Tap again to remove a cell.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Display: ${targets[ratio]} · change in List settings'),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Rows: '),
                          DropdownButton<int>(
                            value: rows,
                            items: [
                              for (var i = 1; i <= 4; i++)
                                DropdownMenuItem(value: i, child: Text('$i')),
                            ],
                            onChanged: (v) {
                              if (v != null)
                                setState(() {
                                  rows = v;
                                  cells = {};
                                });
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Columns: '),
                          DropdownButton<int>(
                            value: columns,
                            items: [
                              for (var i = 1; i <= 4; i++)
                                DropdownMenuItem(value: i, child: Text('$i')),
                            ],
                            onChanged: (v) {
                              if (v != null)
                                setState(() {
                                  columns = v;
                                  cells = {};
                                });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.images.length > 1)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < widget.images.length; i++)
                          ChoiceChip(
                            label: Text('Image ${i + 1}'),
                            selected: i == imageIndex,
                            onSelected: (_) => setState(() => imageIndex = i),
                          ),
                      ],
                    ),
                  Wrap(
                    spacing: 20,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: panelWidth,
                        child: Column(
                          children: [
                            const Text('Choose image area'),
                            const SizedBox(height: 8),
                            AspectRatio(
                              aspectRatio: ratio,
                              child: Column(
                                children: [
                                  for (var r = 0; r < rows; r++)
                                    Expanded(
                                      child: Row(
                                        children: [
                                          for (
                                            var col = 0;
                                            col < columns;
                                            col++
                                          )
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  2,
                                                ),
                                                child: Semantics(
                                                  button: true,
                                                  selected: cells.contains(
                                                    r * columns + col,
                                                  ),
                                                  label:
                                                      'Image cell ${r + 1}, ${col + 1}',
                                                  child: Material(
                                                    color:
                                                        cells.contains(
                                                          r * columns + col,
                                                        )
                                                        ? Theme.of(context)
                                                              .colorScheme
                                                              .primaryContainer
                                                        : Theme.of(context)
                                                              .colorScheme
                                                              .surfaceContainerHighest,
                                                    child: InkWell(
                                                      onTap: () => setState(() {
                                                        final cell =
                                                            r * columns + col;
                                                        if (!cells.add(cell))
                                                          cells.remove(cell);
                                                      }),
                                                      child: Center(
                                                        child: Icon(
                                                          cells.contains(
                                                                r * columns +
                                                                    col,
                                                              )
                                                              ? Icons.image
                                                              : Icons.add,
                                                          size: 20,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              chosen == null
                                  ? 'Select a solid rectangle without gaps.'
                                  : 'Image area selected. Text uses the remaining space.',
                              style: TextStyle(
                                color: chosen == null
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: panelWidth,
                        child: Column(
                          children: [
                            const Text('Preview'),
                            const SizedBox(height: 8),
                            AspectRatio(
                              aspectRatio: ratio,
                              child: Container(
                                color: const Color(0xff14171d),
                                padding: const EdgeInsets.all(8),
                                child: chosen == null || widget.images.isEmpty
                                    ? const Center(
                                        child: Icon(
                                          Icons.grid_view,
                                          color: Colors.white,
                                        ),
                                      )
                                    : NoteImageFlow(
                                        text: widget.text,
                                        formatJson: alignments.withFormat(widget.formatJson),
                                        layout: chosen,
                                        style: const TextStyle(
                                          fontSize: 28,
                                          height: 1.2,
                                          color: Colors.white,
                                        ),
                                        image: Image.memory(
                                          widget.images[imageIndex],
                                          fit: fill
                                              ? BoxFit.cover
                                              : BoxFit.contain,
                                          errorBuilder: (_, _, _) =>
                                              const Icon(Icons.broken_image),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fill selected area'),
                    subtitle: const Text(
                      'Scales proportionally; edges may be cropped. Turn off to show the entire image.',
                    ),
                    value: fill,
                    onChanged: (v) => setState(() => fill = v),
                  ),
                  ExpansionTile(
                    title: const Text('Header and footer'),
                    expansionAnimationStyle: const AnimationStyle(duration: Duration.zero),
                    onExpansionChanged:(expanded) {
                      if(expanded) WidgetsBinding.instance.addPostFrameCallback((_) {
                        if(mounted && _scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);
                      });
                    },
                    children: [
                      BlockAlignmentButtons(value:alignments.title,onChanged:(v)=>setState(()=>alignments=PresentationBlockAlignments(title:v,body:alignments.body,footer:alignments.footer,citation:alignments.citation))),
                      TextField(
                        textAlign:alignments.title,
                        controller: header,
                        decoration: const InputDecoration(
                          labelText: 'Header (optional)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      BlockAlignmentButtons(value:alignments.footer,onChanged:(v)=>setState(()=>alignments=PresentationBlockAlignments(title:alignments.title,body:alignments.body,footer:v,citation:alignments.citation))),
                      TextField(
                        textAlign:alignments.footer,
                        controller: footer,
                        decoration: const InputDecoration(
                          labelText: 'Footer (optional)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const NoteImageLayoutResult(null)),
          child: const Text('Automatic layout'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: chosen == null || widget.images.isEmpty
              ? null
              : () => Navigator.of(context).pop(NoteImageLayoutResult(chosen, alignments)),
          child: const Text('Use layout'),
        ),
      ],
    );
  }
}

class BlockAlignmentButtons extends StatelessWidget {
  const BlockAlignmentButtons({super.key,required this.value,required this.onChanged});
  final TextAlign value;
  final ValueChanged<TextAlign> onChanged;
  @override
  Widget build(BuildContext context)=>Wrap(spacing:2,children:[
    for(final pair in [(TextAlign.left,Icons.format_align_left,'Left'),(TextAlign.center,Icons.format_align_center,'Center'),(TextAlign.right,Icons.format_align_right,'Right'),(TextAlign.justify,Icons.format_align_justify,'Justified')])
      IconButton(tooltip:pair.$3,isSelected:value==pair.$1,onPressed:()=>onChanged(pair.$1),
        style:IconButton.styleFrom(minimumSize:const Size(32,32),padding:const EdgeInsets.all(6)),
        icon:Icon(pair.$2,size:20)),
  ]);
}
