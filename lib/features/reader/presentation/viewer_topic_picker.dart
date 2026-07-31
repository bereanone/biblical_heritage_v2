import 'package:flutter/material.dart';

import '../data/topic_picker_service.dart';
import 'viewer_topic_picker_widgets.dart';

Future<int?> showViewerTopicPicker(
  BuildContext context, {
  required double fontScale,
}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Topics',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, __) {
      return Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final dialogWidth = maxWidth < 700
                ? maxWidth * 0.85
                : maxWidth < 1100
                ? maxWidth * 0.62
                : 560.0;
            return SizedBox(
              width: dialogWidth.clamp(280.0, 560.0),
              height: constraints.maxHeight * 0.98,
              child: SafeArea(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 8,
                  child: ViewerTopicPicker(fontScale: fontScale),
                ),
              ),
            );
          },
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class ViewerTopicPicker extends StatefulWidget {
  const ViewerTopicPicker({super.key, required this.fontScale});

  final double fontScale;

  @override
  State<ViewerTopicPicker> createState() => _ViewerTopicPickerState();
}

class _ViewerTopicPickerState extends State<ViewerTopicPicker> {
  final ScrollController _topicsScrollController = ScrollController();
  TopicPickerData? _data;
  int? _selectedSectionId;
  int? _selectedBookNumber;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topicsScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await TopicPickerService.instance.load();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _buildLoaded(context, constraints);
        },
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, BoxConstraints constraints) {
    final data = _data!;
    final filteredTopics = _filteredTopics();
    final selectedSection = _selectedSection();
    final sectionItems = _sectionGraphItems();
    final bookItems = _bookGraphItems(selectedSection);
    final summaryHeight = resolvedViewerTopicSummaryBarHeight(widget.fontScale);
    final chromeHeight = summaryHeight + 1.0 + 1.0;
    final availableAfterChrome = (constraints.maxHeight - chromeHeight).clamp(
      0.0,
      constraints.maxHeight,
    );
    double graphMaxHeight = availableAfterChrome - 140.0;
    if (graphMaxHeight < 72.0) {
      graphMaxHeight = availableAfterChrome * 0.55;
    }
    graphMaxHeight = graphMaxHeight.clamp(0.0, availableAfterChrome);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ViewerTopicSummaryBar(
          total: data.topics.length,
          onClose: () => Navigator.of(context, rootNavigator: true).pop(),
          fontScale: widget.fontScale,
          isFiltered: _selectedSectionId != null || _selectedBookNumber != null,
          onReset: () {
            setState(() {
              _selectedSectionId = null;
              _selectedBookNumber = null;
            });
          },
        ),
        const Divider(height: 0.5, thickness: 0.5),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: graphMaxHeight),
          child: ViewerTopicOverlayGraphArea(
            sectionItems: sectionItems,
            selectedBookItems: bookItems,
            sectionSelected: selectedSection != null,
            selectedSectionLabel: selectedSection?.name,
            onTapSection: _toggleSection,
            onTapBook: _toggleBook,
            onBackToSections: () {
              setState(() {
                _selectedSectionId = null;
                _selectedBookNumber = null;
              });
            },
            fontScale: widget.fontScale,
            maxHeight: graphMaxHeight,
          ),
        ),
        const Divider(height: 0.5, thickness: 0.5),
        Expanded(
          child: Scrollbar(
            controller: _topicsScrollController,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _topicsScrollController,
              padding: EdgeInsets.zero,
              itemCount: filteredTopics.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 0.5, thickness: 0.5),
              itemBuilder: (context, index) {
                final topic = filteredTopics[index];
                final topicFontSize = (14.0 * widget.fontScale).clamp(
                  13.0,
                  22.0,
                );
                final topicRowHeight = (topicFontSize * 1.9).clamp(30.0, 54.0);
                const nameStyle = TextStyle(height: 1.1);
                return InkWell(
                  onTap: () {
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(topic.blockId);
                  },
                  child: SizedBox(
                    height: topicRowHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            topic.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle.copyWith(fontSize: topicFontSize),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<TopicEntry> _filteredTopics() {
    final data = _data!;
    return data.topics
        .where((topic) {
          if (_selectedSectionId != null) {
            final section = data.sections
                .where((item) => item.id == _selectedSectionId)
                .cast<TopicSection?>()
                .firstWhere((item) => item != null, orElse: () => null);
            if (section == null) return false;
            if (topic.blockId < section.minBlockId ||
                topic.blockId > section.maxBlockId) {
              return false;
            }
          }
          if (_selectedBookNumber != null &&
              topic.bookNumber != _selectedBookNumber) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  TopicSection? _selectedSection() {
    return _data!.sections
        .where((section) => section.id == _selectedSectionId)
        .cast<TopicSection?>()
        .firstWhere((section) => section != null, orElse: () => null);
  }

  List<ViewerTopicGraphItem> _sectionGraphItems() {
    final data = _data!;
    return data.sections
        .map((section) {
          final count = data.topics
              .where(
                (topic) =>
                    topic.blockId >= section.minBlockId &&
                    topic.blockId <= section.maxBlockId,
              )
              .length;
          return ViewerTopicGraphItem(
            id: section.id,
            label: section.name,
            count: count,
            color: _parseHexColor(section.colorHex),
          );
        })
        .toList(growable: false);
  }

  List<ViewerTopicGraphItem> _bookGraphItems(TopicSection? section) {
    if (section == null) return const [];
    final data = _data!;
    final filteredBySection = data.topics.where(
      (topic) =>
          topic.blockId >= section.minBlockId &&
          topic.blockId <= section.maxBlockId,
    );
    final counts = <int, int>{};
    for (final topic in filteredBySection) {
      counts.update(topic.bookNumber, (value) => value + 1, ifAbsent: () => 1);
    }
    return data.books
        .where((book) => counts.containsKey(book.bookNumber))
        .map(
          (book) => ViewerTopicGraphItem(
            id: book.bookNumber,
            label: book.bookName,
            count: counts[book.bookNumber] ?? 0,
            color: _parseHexColor(section.colorHex),
          ),
        )
        .toList(growable: false);
  }

  void _toggleSection(int id) {
    setState(() {
      if (_selectedSectionId == id) {
        _selectedSectionId = null;
        _selectedBookNumber = null;
      } else {
        _selectedSectionId = id;
        _selectedBookNumber = null;
      }
    });
  }

  void _toggleBook(int bookNumber) {
    setState(() {
      if (_selectedBookNumber == bookNumber) {
        _selectedBookNumber = null;
      } else {
        _selectedBookNumber = bookNumber;
      }
    });
  }

  Color _parseHexColor(String value) {
    final hex = value.replaceFirst('#', '');
    if (hex.length != 6) {
      return const Color(0xFFB39F8F);
    }
    return Color(int.parse('FF$hex', radix: 16));
  }
}
