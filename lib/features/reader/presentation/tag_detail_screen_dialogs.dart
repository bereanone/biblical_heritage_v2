part of 'tag_detail_screen.dart';

class _ContentItemDialog extends StatefulWidget {
  const _ContentItemDialog({
    required this.repository,
    required this.tag,
    required this.fontScale,
  });

  final HashTagRepository repository;
  final String tag;
  final double fontScale;

  @override
  State<_ContentItemDialog> createState() => _ContentItemDialogState();
}

class _ContentItemDialogState extends State<_ContentItemDialog> {
  static const MethodChannel _clipboardImageChannel = MethodChannel(
    'studybible/image_paste',
  );

  late final _RichNoteController _noteController;
  final FocusNode _noteFocusNode = FocusNode();
  final TextEditingController _referenceController = TextEditingController();
  final List<_StagedMediaAttachment> _media = <_StagedMediaAttachment>[];
  PresentationTextFormat? _noteFormat;
  bool _saving = false;
  String _lastNoteText = '';

  @override
  void initState() {
    super.initState();
    PasteChannel.instance.initialize();
    _noteController = _RichNoteController(
      formatResolver: () => _noteFormat,
      baseStyleResolver: () => _noteBaseStyle(Theme.of(context)),
    );
    _noteController.addListener(_handleNoteChanged);
    _lastNoteText = _noteController.text;
  }

  @override
  void dispose() {
    _noteController.removeListener(_handleNoteChanged);
    _noteController.dispose();
    _noteFocusNode.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  TextStyle _noteBaseStyle(ThemeData theme) {
    return TextStyle(
      color: TagDialogStyles.body(theme),
      fontFamily: 'Roboto',
      fontSize: TagDialogStyles.scaledFontSize(
        theme.textTheme.bodyMedium?.fontSize,
        widget.fontScale,
      ),
      fontWeight: FontWeight.w400,
      height: 1.28,
      decorationColor: TagDialogStyles.body(theme),
    );
  }

  void _handleNoteChanged() {
    final currentText = _noteController.text;
    if (currentText == _lastNoteText) return;

    final updatedFormat = _adjustFormatForTextChange(
      format: _noteFormat,
      previousText: _lastNoteText,
      currentText: currentText,
    );
    _lastNoteText = currentText;
    if (updatedFormat == _noteFormat) {
      return;
    }
    _noteFormat = updatedFormat;
    _noteController.refreshRichText();
  }

  PresentationTextFormat? _adjustFormatForTextChange({
    required PresentationTextFormat? format,
    required String previousText,
    required String currentText,
  }) {
    if (format == null || format.spans.isEmpty || previousText == currentText) {
      return format;
    }

    final delta = _computeTextChangeDelta(previousText, currentText);
    if (delta == null) return format;

    final shift = delta.insertedLength - delta.removedLength;
    final updated = <PresentationTextSpanRange>[];

    for (final span in format.spans) {
      if (span.end <= delta.start) {
        updated.add(span);
        continue;
      }
      if (span.start >= delta.oldEnd) {
        updated.add(
          span.copyWith(start: span.start + shift, end: span.end + shift),
        );
        continue;
      }

      if (span.start < delta.start) {
        final leftEnd = delta.start.clamp(span.start, span.end).toInt();
        if (leftEnd > span.start) {
          updated.add(span.copyWith(end: leftEnd));
        }
      }

      if (delta.insertedLength > 0 &&
          span.start < delta.oldEnd &&
          span.end > delta.start) {
        updated.add(
          PresentationTextSpanRange(
            start: delta.start,
            end: delta.start + delta.insertedLength,
            style: span.style,
          ),
        );
      }

      if (span.end > delta.oldEnd) {
        final start =
            (span.start < delta.oldEnd ? delta.newEnd : span.start + shift)
                .clamp(0, currentText.length)
                .toInt();
        final end = (span.end + shift).clamp(0, currentText.length).toInt();
        if (end > start) {
          updated.add(span.copyWith(start: start, end: end));
        }
      }
    }

    return PresentationTextFormat(
      baseTextHash: null,
      spans: _mergePresentationSpans(updated, currentText.length),
    );
  }

  _TextChangeDelta? _computeTextChangeDelta(
    String previousText,
    String currentText,
  ) {
    if (previousText == currentText) return null;

    var start = 0;
    while (start < previousText.length &&
        start < currentText.length &&
        previousText.codeUnitAt(start) == currentText.codeUnitAt(start)) {
      start++;
    }

    var previousEnd = previousText.length;
    var currentEnd = currentText.length;
    while (previousEnd > start &&
        currentEnd > start &&
        previousText.codeUnitAt(previousEnd - 1) ==
            currentText.codeUnitAt(currentEnd - 1)) {
      previousEnd--;
      currentEnd--;
    }

    return _TextChangeDelta(
      start: start,
      oldEnd: previousEnd,
      newEnd: currentEnd,
    );
  }

  Future<void> _pasteImageFromClipboard() async {
    if (_saving) return;
    final nativeBytes = await _readClipboardImageBytes();
    if (nativeBytes != null && nativeBytes.isNotEmpty) {
      await _stageImageBytes(nativeBytes, 'image/png');
      if (mounted) {
        setState(() {});
      }
      return;
    }

    try {
      final payload = await PasteChannel.instance.getPastePayload();
      switch (payload) {
        case RawImagePaste(:final items):
          var stagedAny = false;
          for (final item in items) {
            stagedAny =
                await _stageImageBytes(item.data, item.mimeType) || stagedAny;
          }
          if (stagedAny && mounted) {
            setState(() {});
          }
        case ImagePaste(:final uris, :final mimeTypes):
          var stagedAny = false;
          for (var index = 0; index < uris.length; index++) {
            final mimeType = index < mimeTypes.length
                ? mimeTypes[index]
                : 'image/png';
            stagedAny =
                await _stageImageFile(uris[index], mimeType) || stagedAny;
          }
          if (stagedAny && mounted) {
            setState(() {});
          }
        case TextPaste():
        case UnsupportedPaste():
          _showSnack('Clipboard does not contain an image.');
      }
    } catch (_) {
      _showSnack('Clipboard does not contain an image.');
    }
  }

  Future<Uint8List?> _readClipboardImageBytes() async {
    if (!Platform.isMacOS) return null;
    try {
      final result = await _clipboardImageChannel.invokeMethod<dynamic>(
        'pasteImageFromClipboard',
      );
      if (result is Uint8List) return result;
      if (result is ByteData) {
        return result.buffer.asUint8List(
          result.offsetInBytes,
          result.lengthInBytes,
        );
      }
      if (result is List<int>) return Uint8List.fromList(result);
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _stageImageBytes(Uint8List bytes, String mimeType) async {
    _media.add(
      _StagedMediaAttachment(
        bytes: bytes,
        mimeType: mimeType.isEmpty ? 'image/png' : mimeType,
      ),
    );
    return true;
  }

  Future<bool> _stageImageFile(String sourcePath, String mimeType) async {
    final path = sourcePath.startsWith('file://')
        ? Uri.parse(sourcePath).toFilePath()
        : sourcePath;
    final file = File(path);
    if (!file.existsSync()) return false;
    final bytes = await file.readAsBytes();
    await _stageImageBytes(bytes, mimeType);
    try {
      final tempDir = await getTemporaryDirectory();
      final normalizedSource = p.normalize(path);
      final normalizedTemp = p.normalize(tempDir.path);
      if (p.isWithin(normalizedTemp, normalizedSource) ||
          normalizedSource.startsWith('$normalizedTemp${p.separator}')) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup only.
    }
    return true;
  }

  Future<String> _mediaBasePath() async {
    final libraryRoot = await LibraryRootService.instance.libraryRootPath();
    if (libraryRoot != null && libraryRoot.trim().isNotEmpty) {
      return libraryRoot;
    }
    final support = await getApplicationSupportDirectory();
    final fallback = p.join(support.path, 'studybible_media');
    await Directory(p.join(fallback, 'Media')).create(recursive: true);
    return fallback;
  }

  String _extensionForMimeType(String mimeType) {
    return switch (mimeType.trim().toLowerCase()) {
      'image/jpeg' => '.jpg',
      'image/jpg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      _ => '.img',
    };
  }

  String? _noteFormatJsonForCurrentText(String text) {
    return presentationTextFormatJsonForText(text: text, format: _noteFormat);
  }

  Future<void> _toggleFormat(PresentationTextDecorationKind kind) async {
    final selection = _noteController.selection;
    if (selection.isCollapsed) {
      _showSnack('Select text first.');
      return;
    }
    final updated = togglePresentationTextDecoration(
      text: _noteController.text,
      current: _noteFormat,
      selection: selection,
      kind: kind,
    );
    if (updated == null) {
      _showSnack('Select text first.');
      return;
    }
    setState(() {
      _noteFormat = updated;
    });
    _noteController.refreshRichText();
  }

  void _removeMediaAt(int index) {
    if (index < 0 || index >= _media.length) return;
    _media.removeAt(index);
    setState(() {});
  }

  Widget _formatButton(
    IconData icon,
    String label,
    PresentationTextDecorationKind kind,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: _saving ? null : () => _toggleFormat(kind),
        radius: 18,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TagDialogStyles.surfaceHigh(theme),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: TagDialogStyles.outlineColor(theme),
            ),
          ),
          child: Icon(icon, size: 18, color: TagDialogStyles.title(theme)),
        ),
      ),
    );
  }

  Widget _buildMediaTile(_StagedMediaAttachment attachment, int index) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 112,
            height: 84,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Image.memory(attachment.bytes, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Material(
            color: TagDialogStyles.surfaceHigh(theme),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _saving ? null : () => _removeMediaAt(index),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: TagDialogStyles.title(theme),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final noteText = _noteController.text.trim();
    final referenceCode = _referenceController.text.trim();
    if (noteText.isEmpty && referenceCode.isEmpty && _media.isEmpty) {
      _showSnack('Add note text or media before saving.');
      return;
    }

    setState(() {
      _saving = true;
    });

    final noteFormatJson = noteText.isEmpty
        ? null
        : _noteFormatJsonForCurrentText(noteText);

    try {
      final inserted = await widget.repository.insertNoteItem(
        tag: widget.tag,
        noteText: noteText,
        referenceCode: referenceCode,
        noteFormatJson: noteFormatJson,
        allowBlank: _media.isNotEmpty,
      );
      if (inserted <= 0) {
        throw StateError('No row was inserted.');
      }

      final createdFiles = <File>[];
      try {
        for (var index = 0; index < _media.length; index++) {
          final attachment = _media[index];
          final persisted = await _persistMediaAttachment(attachment);
          createdFiles.add(File(persisted.absolutePath));
          await widget.repository.addMediaAttachment(
            entryId: inserted,
            relativePath: persisted.relativePath,
            mimeType: persisted.mimeType,
            fileSize: persisted.fileSize,
            fileHash: persisted.fileHash,
            sortOrder: index,
          );
        }
      } catch (error) {
        for (final file in createdFiles) {
          try {
            if (file.existsSync()) {
              file.deleteSync();
            }
          } catch (_) {
            // Best-effort cleanup.
          }
        }
        await widget.repository.deleteEntry(inserted);
        rethrow;
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
      _showSnack('Could not save content item.');
    }
  }

  Future<_PersistedMediaAttachment> _persistMediaAttachment(
    _StagedMediaAttachment attachment,
  ) async {
    final rootPath = await _mediaBasePath();
    final mediaDir = Directory(p.join(rootPath, 'Media', 'tag_content'));
    await mediaDir.create(recursive: true);
    final hash = sha256.convert(attachment.bytes).toString();
    final extension = _extensionForMimeType(attachment.mimeType);
    final fileName =
        'content_${DateTime.now().millisecondsSinceEpoch}_$hash$extension';
    final absolutePath = p.join(mediaDir.path, fileName);
    final file = File(absolutePath);
    await file.writeAsBytes(attachment.bytes, flush: true);
    return _PersistedMediaAttachment(
      absolutePath: absolutePath,
      relativePath: p.relative(absolutePath, from: rootPath),
      mimeType: attachment.mimeType,
      fileHash: hash,
      fileSize: attachment.bytes.length,
    );
  }

  List<PresentationTextSpanRange> _mergePresentationSpans(
    List<PresentationTextSpanRange> spans,
    int textLength,
  ) {
    final normalized = <PresentationTextSpanRange>[];
    for (final span in spans) {
      final start = span.start.clamp(0, textLength).toInt();
      final end = span.end.clamp(0, textLength).toInt();
      if (end <= start) continue;
      normalized.add(span.copyWith(start: start, end: end));
    }
    normalized.sort((a, b) => a.start.compareTo(b.start));
    if (normalized.isEmpty) return normalized;

    final merged = <PresentationTextSpanRange>[normalized.first];
    for (var i = 1; i < normalized.length; i++) {
      final current = normalized[i];
      final last = merged.last;
      if (current.start == last.end &&
          current.style.bold == last.style.bold &&
          current.style.underline == last.style.underline &&
          current.style.italic == last.style.italic) {
        merged[merged.length - 1] = last.copyWith(end: current.end);
        continue;
      }
      merged.add(current);
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = TagDialogStyles.title(theme);
    final bodyColor = TagDialogStyles.body(theme);
    final outlineColor = TagDialogStyles.outlineColor(theme);
    return AlertDialog(
      title: Text(
        'Add Content Item',
        style: TagDialogStyles.titleTextStyle(
          theme,
          widget.fontScale,
          color: titleColor,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Note',
                style: TagDialogStyles.labelTextStyle(
                  theme,
                  widget.fontScale,
                  color: titleColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _formatButton(
                    Icons.format_bold,
                    'Bold selected text',
                    PresentationTextDecorationKind.bold,
                  ),
                  const SizedBox(width: 6),
                  _formatButton(
                    Icons.format_underline,
                    'Underline selected text',
                    PresentationTextDecorationKind.underline,
                  ),
                  const SizedBox(width: 6),
                  _formatButton(
                    Icons.format_italic,
                    'Italic selected text',
                    PresentationTextDecorationKind.italic,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Select text first, then tap B, U, or I.',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: bodyColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PasteWrapper(
                acceptedTypes: {PasteType.image},
                saveImagesToTempFiles: false,
                onPaste: (payload) async {
                  var stagedAny = false;
                  switch (payload) {
                    case RawImagePaste(:final items):
                      for (final item in items) {
                        stagedAny =
                            await _stageImageBytes(item.data, item.mimeType) ||
                            stagedAny;
                      }
                    case ImagePaste(:final uris, :final mimeTypes):
                      final bytes = await _readClipboardImageBytes();
                      if (bytes != null && bytes.isNotEmpty) {
                        stagedAny =
                            await _stageImageBytes(bytes, 'image/png') ||
                            stagedAny;
                      } else {
                        for (var index = 0; index < uris.length; index++) {
                          final mimeType = index < mimeTypes.length
                              ? mimeTypes[index]
                              : 'image/png';
                          stagedAny =
                              await _stageImageFile(uris[index], mimeType) ||
                              stagedAny;
                        }
                      }
                    case TextPaste():
                    case UnsupportedPaste():
                      break;
                  }
                  if (stagedAny && mounted) {
                    setState(() {});
                  }
                },
                child: TextField(
                  controller: _noteController,
                  focusNode: _noteFocusNode,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  style: _noteBaseStyle(theme),
                  decoration: const InputDecoration(
                    labelText: 'Note text',
                    border: OutlineInputBorder(),
                  ).copyWith(
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    hintStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _referenceController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Reference Code',
                  hintText: 'Optional, for example GC 623.2',
                  border: const OutlineInputBorder(),
                  labelStyle: TagDialogStyles.labelTextStyle(
                    theme,
                    widget.fontScale,
                    color: TagDialogStyles.body(theme),
                  ),
                  floatingLabelStyle: TagDialogStyles.labelTextStyle(
                    theme,
                    widget.fontScale,
                    color: TagDialogStyles.title(theme),
                  ),
                  hintStyle: TagDialogStyles.bodyTextStyle(
                    theme,
                    widget.fontScale,
                    color: TagDialogStyles.mutedBody(theme),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.28,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: outlineColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Media',
                            style: TagDialogStyles.labelTextStyle(
                              theme,
                              widget.fontScale,
                              color: titleColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _saving ? null : _pasteImageFromClipboard,
                          icon: const Icon(Icons.content_paste),
                          label: Text(
                            'Paste Image',
                            style: TagDialogStyles.buttonTextStyle(
                              theme,
                              widget.fontScale,
                              color: TagDialogStyles.accent(theme),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  Text(
                    'Paste an image from the clipboard. It will be copied into the app media folder.',
                    style: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: bodyColor,
                      height: 1.25,
                    ),
                  ),
                    const SizedBox(height: 10),
                    if (_media.isEmpty)
                      Text(
                        'No image attached yet.',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: bodyColor,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var index = 0; index < _media.length; index++)
                            _buildMediaTile(_media[index], index),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: Text(
            'Cancel',
            style: TagDialogStyles.buttonTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.body(theme),
            ),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: TagDialogStyles.fittedButtonLabel(
            _saving ? 'Saving…' : 'Save',
            style: TagDialogStyles.buttonTextStyle(
              theme,
              widget.fontScale,
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditEntryNoteDialog extends StatefulWidget {
  const _EditEntryNoteDialog({
    required this.repository,
    required this.entry,
    required this.fontScale,
    required this.title,
    required this.noteLabel,
    required this.canonicalReferenceLabel,
    required this.verseText,
    required this.initialNoteText,
    required this.initialReferenceCode,
    required this.initialUserTitle,
    required this.initialTitleFormatJson,
    required this.initialDisplayTextOverride,
    required this.initialDisplayTextFormatJson,
    required this.initialNoteFormatJson,
    required this.referenceFieldLabel,
    required this.referenceFieldHint,
    required this.initialMedia,
  });

  final HashTagRepository repository;
  final HashTagEntry entry;
  final double fontScale;
  final String title;
  final String noteLabel;
  final String canonicalReferenceLabel;
  final String verseText;
  final String initialNoteText;
  final String initialReferenceCode;
  final String initialUserTitle;
  final String? initialTitleFormatJson;
  final String initialDisplayTextOverride;
  final String? initialDisplayTextFormatJson;
  final String? initialNoteFormatJson;
  final String referenceFieldLabel;
  final String referenceFieldHint;
  final List<_StagedMediaAttachment> initialMedia;

  @override
  State<_EditEntryNoteDialog> createState() => _EditEntryNoteDialogState();
}

class _EditEntryNoteDialogState extends State<_EditEntryNoteDialog> {
  static const MethodChannel _clipboardImageChannel = MethodChannel(
    'studybible/image_paste',
  );

  late final TextEditingController _displayCitationController;
  late final _RichNoteController _titleController;
  late final _RichNoteController _displayTextController;
  late final _RichNoteController _noteController;
  final List<_StagedMediaAttachment> _media = <_StagedMediaAttachment>[];
  PresentationTextFormat? _titleFormat;
  PresentationTextFormat? _displayTextFormat;
  PresentationTextFormat? _noteFormat;
  bool _saving = false;
  String _lastTitleText = '';
  String _lastDisplayText = '';
  String _lastNoteText = '';

  @override
  void initState() {
    super.initState();
    _titleFormat = presentationTextFormatForText(
      text: widget.initialUserTitle,
      json: widget.initialTitleFormatJson,
    );
    _titleController = _RichNoteController(
      formatResolver: () => _titleFormat,
      baseStyleResolver: () => _titleBaseStyle(Theme.of(context)),
    );
    _titleController.text = widget.initialUserTitle;
    _titleController.addListener(_handleTitleChanged);
    _displayTextFormat = presentationTextFormatForText(
      text: widget.initialDisplayTextOverride.isNotEmpty
          ? widget.initialDisplayTextOverride
          : widget.verseText,
      json: widget.initialDisplayTextFormatJson,
    );
    _displayTextController = _RichNoteController(
      formatResolver: () => _displayTextFormat,
      baseStyleResolver: () => _displayTextBaseStyle(Theme.of(context)),
    );
    _displayTextController.text = widget.initialDisplayTextOverride.isNotEmpty
        ? widget.initialDisplayTextOverride
        : widget.verseText;
    _displayTextController.addListener(_handleDisplayTextChanged);
    _noteFormat = presentationTextFormatForText(
      text: widget.initialNoteText,
      json: widget.initialNoteFormatJson,
    );
    _noteController = _RichNoteController(
      formatResolver: () => _noteFormat,
      baseStyleResolver: () => _noteBaseStyle(Theme.of(context)),
    );
    _noteController.text = widget.initialNoteText;
    _noteController.addListener(_handleNoteChanged);
    _displayCitationController = TextEditingController(
      text: widget.initialReferenceCode,
    );
    _media.addAll(widget.initialMedia);
    _lastTitleText = _titleController.text;
    _lastDisplayText = _displayTextController.text;
    _lastNoteText = _noteController.text;
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _titleController.dispose();
    _displayTextController.removeListener(_handleDisplayTextChanged);
    _displayTextController.dispose();
    _noteController.removeListener(_handleNoteChanged);
    _noteController.dispose();
    _displayCitationController.dispose();
    super.dispose();
  }

  bool get _isBibleItem =>
      widget.entry.bookNumber > 0 &&
      widget.entry.chapter > 0 &&
      widget.entry.verse > 0;

  TextStyle _noteBaseStyle(ThemeData theme) {
    return TextStyle(
      color: TagDialogStyles.body(theme),
      fontFamily: 'Roboto',
      fontSize: TagDialogStyles.scaledFontSize(
        theme.textTheme.bodyMedium?.fontSize,
        widget.fontScale,
      ),
      fontWeight: FontWeight.w400,
      height: 1.28,
      decorationColor: TagDialogStyles.body(theme),
    );
  }

  TextStyle _displayTextBaseStyle(ThemeData theme) {
    return TextStyle(
      color: TagDialogStyles.body(theme),
      fontFamily: 'Roboto',
      fontSize: TagDialogStyles.scaledFontSize(
        theme.textTheme.bodyMedium?.fontSize,
        widget.fontScale,
      ),
      fontWeight: FontWeight.w400,
      height: 1.28,
      decorationColor: TagDialogStyles.body(theme),
    );
  }

  TextStyle _titleBaseStyle(ThemeData theme) {
    return TextStyle(
      color: TagDialogStyles.title(theme),
      fontFamily: 'Roboto',
      fontSize: TagDialogStyles.scaledFontSize(
        theme.textTheme.titleMedium?.fontSize,
        widget.fontScale,
      ),
      fontWeight: FontWeight.w800,
      height: 1.15,
      decorationColor: TagDialogStyles.title(theme),
    );
  }

  void _handleTitleChanged() {
    final currentText = _titleController.text;
    if (currentText == _lastTitleText) return;
    final updatedFormat = _adjustFormatForTextChange(
      format: _titleFormat,
      previousText: _lastTitleText,
      currentText: currentText,
    );
    _lastTitleText = currentText;
    if (updatedFormat == _titleFormat) return;
    _titleFormat = updatedFormat;
    _titleController.refreshRichText();
  }

  void _handleDisplayTextChanged() {
    final currentText = _displayTextController.text;
    if (currentText == _lastDisplayText) return;
    final updatedFormat = _adjustFormatForTextChange(
      format: _displayTextFormat,
      previousText: _lastDisplayText,
      currentText: currentText,
    );
    _lastDisplayText = currentText;
    if (updatedFormat == _displayTextFormat) return;
    _displayTextFormat = updatedFormat;
    _displayTextController.refreshRichText();
  }

  void _handleNoteChanged() {
    final currentText = _noteController.text;
    if (currentText == _lastNoteText) return;
    final updatedFormat = _adjustFormatForTextChange(
      format: _noteFormat,
      previousText: _lastNoteText,
      currentText: currentText,
    );
    _lastNoteText = currentText;
    if (updatedFormat == _noteFormat) return;
    _noteFormat = updatedFormat;
    _noteController.refreshRichText();
  }

  PresentationTextFormat? _adjustFormatForTextChange({
    required PresentationTextFormat? format,
    required String previousText,
    required String currentText,
  }) {
    if (format == null || format.spans.isEmpty || previousText == currentText) {
      return format;
    }

    final delta = _computeTextChangeDelta(previousText, currentText);
    if (delta == null) return format;

    final shift = delta.insertedLength - delta.removedLength;
    final updated = <PresentationTextSpanRange>[];

    for (final span in format.spans) {
      if (span.end <= delta.start) {
        updated.add(span);
        continue;
      }
      if (span.start >= delta.oldEnd) {
        updated.add(
          span.copyWith(start: span.start + shift, end: span.end + shift),
        );
        continue;
      }

      if (span.start < delta.start) {
        final leftEnd = delta.start.clamp(span.start, span.end).toInt();
        if (leftEnd > span.start) {
          updated.add(span.copyWith(end: leftEnd));
        }
      }

      if (delta.insertedLength > 0 &&
          span.start < delta.oldEnd &&
          span.end > delta.start) {
        updated.add(
          PresentationTextSpanRange(
            start: delta.start,
            end: delta.start + delta.insertedLength,
            style: span.style,
          ),
        );
      }

      if (span.end > delta.oldEnd) {
        final start =
            (span.start < delta.oldEnd ? delta.newEnd : span.start + shift)
                .clamp(0, currentText.length)
                .toInt();
        final end = (span.end + shift).clamp(0, currentText.length).toInt();
        if (end > start) {
          updated.add(span.copyWith(start: start, end: end));
        }
      }
    }

    return PresentationTextFormat(
      baseTextHash: null,
      spans: _mergePresentationSpans(updated, currentText.length),
    );
  }

  _TextChangeDelta? _computeTextChangeDelta(
    String previousText,
    String currentText,
  ) {
    if (previousText == currentText) return null;

    var start = 0;
    while (start < previousText.length &&
        start < currentText.length &&
        previousText.codeUnitAt(start) == currentText.codeUnitAt(start)) {
      start++;
    }

    var previousEnd = previousText.length;
    var currentEnd = currentText.length;
    while (previousEnd > start &&
        currentEnd > start &&
        previousText.codeUnitAt(previousEnd - 1) ==
            currentText.codeUnitAt(currentEnd - 1)) {
      previousEnd--;
      currentEnd--;
    }

    return _TextChangeDelta(
      start: start,
      oldEnd: previousEnd,
      newEnd: currentEnd,
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _extensionForMimeType(String mimeType) {
    return switch (mimeType.trim().toLowerCase()) {
      'image/jpeg' => '.jpg',
      'image/jpg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      _ => '.img',
    };
  }

  Future<String> _mediaBasePath() async {
    final libraryRoot = await LibraryRootService.instance.libraryRootPath();
    if (libraryRoot != null && libraryRoot.trim().isNotEmpty) {
      return libraryRoot;
    }
    final support = await getApplicationSupportDirectory();
    final fallback = p.join(support.path, 'studybible_media');
    await Directory(p.join(fallback, 'Media')).create(recursive: true);
    return fallback;
  }

  Future<void> _deleteMediaFilesForRefs(List<String> mediaRefs) async {
    final basePath = await _mediaBasePath();
    for (final mediaRef in mediaRefs) {
      try {
        final normalized = mediaRef.trim();
        if (normalized.isEmpty) continue;
        final path = p.isAbsolute(normalized)
            ? normalized
            : p.join(basePath, p.normalize(normalized));
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  Future<_PersistedMediaAttachment> _persistMediaAttachment(
    _StagedMediaAttachment attachment,
  ) async {
    final rootPath = await _mediaBasePath();
    final mediaDir = Directory(p.join(rootPath, 'Media', 'tag_content'));
    await mediaDir.create(recursive: true);
    final hash = sha256.convert(attachment.bytes).toString();
    final extension = _extensionForMimeType(attachment.mimeType);
    final fileName =
        'content_${DateTime.now().millisecondsSinceEpoch}_$hash$extension';
    final absolutePath = p.join(mediaDir.path, fileName);
    final file = File(absolutePath);
    await file.writeAsBytes(attachment.bytes, flush: true);
    return _PersistedMediaAttachment(
      absolutePath: absolutePath,
      relativePath: p.relative(absolutePath, from: rootPath),
      mimeType: attachment.mimeType,
      fileHash: hash,
      fileSize: attachment.bytes.length,
    );
  }

  Future<Uint8List?> _readClipboardImageBytes() async {
    if (!Platform.isMacOS) return null;
    try {
      final result = await _clipboardImageChannel.invokeMethod<dynamic>(
        'pasteImageFromClipboard',
      );
      if (result is Uint8List) return result;
      if (result is ByteData) {
        return result.buffer.asUint8List(
          result.offsetInBytes,
          result.lengthInBytes,
        );
      }
      if (result is List<int>) return Uint8List.fromList(result);
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _stageImageBytes(Uint8List bytes, String mimeType) async {
    _media.add(
      _StagedMediaAttachment(
        bytes: bytes,
        mimeType: mimeType.isEmpty ? 'image/png' : mimeType,
      ),
    );
    return true;
  }

  Future<bool> _stageImageFile(String sourcePath, String mimeType) async {
    final path = sourcePath.startsWith('file://')
        ? Uri.parse(sourcePath).toFilePath()
        : sourcePath;
    final file = File(path);
    if (!file.existsSync()) return false;
    final bytes = await file.readAsBytes();
    await _stageImageBytes(bytes, mimeType);
    return true;
  }

  Future<void> _pasteImageFromClipboard() async {
    if (_saving) return;
    final nativeBytes = await _readClipboardImageBytes();
    if (nativeBytes != null && nativeBytes.isNotEmpty) {
      await _stageImageBytes(nativeBytes, 'image/png');
      if (mounted) {
        setState(() {});
      }
      return;
    }

    try {
      final payload = await PasteChannel.instance.getPastePayload();
      switch (payload) {
        case RawImagePaste(:final items):
          var stagedAny = false;
          for (final item in items) {
            stagedAny =
                await _stageImageBytes(item.data, item.mimeType) || stagedAny;
          }
          if (stagedAny && mounted) {
            setState(() {});
          }
        case ImagePaste(:final uris, :final mimeTypes):
          var stagedAny = false;
          for (var index = 0; index < uris.length; index++) {
            final mimeType = index < mimeTypes.length
                ? mimeTypes[index]
                : 'image/png';
            stagedAny =
                await _stageImageFile(uris[index], mimeType) || stagedAny;
          }
          if (stagedAny && mounted) {
            setState(() {});
          }
        case TextPaste():
        case UnsupportedPaste():
          _showSnack('Clipboard does not contain an image.');
      }
    } catch (_) {
      _showSnack('Clipboard does not contain an image.');
    }
  }

  void _removeMediaAt(int index) {
    if (index < 0 || index >= _media.length) return;
    _media.removeAt(index);
    setState(() {});
  }

  Widget _buildMediaTile(_StagedMediaAttachment attachment, int index) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 112,
            height: 84,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Image.memory(attachment.bytes, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Material(
            color: TagDialogStyles.surfaceHigh(theme),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _saving ? null : () => _removeMediaAt(index),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: TagDialogStyles.title(theme),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final noteText = _noteController.text.trim();
    final displayCitation = _displayCitationController.text.trim();
    final userTitle = _titleController.text.trim();
    final displayText = _displayTextController.text.trim();
    final sourceDisplayText = widget.verseText.trim();
    final shouldPersistDisplayText =
        displayText.isNotEmpty &&
        (displayText != sourceDisplayText || _displayTextFormat != null);
    final displayTextOverride =
        shouldPersistDisplayText ? displayText : null;
    if (noteText.isEmpty &&
        displayCitation.isEmpty &&
        userTitle.isEmpty &&
        (displayTextOverride ?? '').isEmpty &&
        _media.isEmpty) {
      if (!_isBibleItem) {
        await widget.repository.deleteMediaAttachmentsForEntry(widget.entry.id);
        await _deleteMediaFilesForRefs(widget.entry.mediaRefs);
        await widget.repository.deleteEntry(
          widget.entry.id,
          normalized: widget.entry.isNormalized,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    final noteFormatJson = noteText.isEmpty
        ? null
        : presentationTextFormatJsonForText(text: noteText, format: _noteFormat);
    final titleFormatJson = userTitle.isEmpty
        ? null
        : presentationTextFormatJsonForText(
            text: userTitle,
            format: _titleFormat,
          );
    final displayTextFormatJson = displayTextOverride == null
        ? null
        : presentationTextFormatJsonForText(
            text: displayTextOverride,
            format: _displayTextFormat,
          );
    final overlayJson = _isBibleItem
        ? buildBibleItemOverlayJson(
            userTitle: userTitle,
            displayTextOverride: displayTextOverride,
            noteFormatJson: noteFormatJson,
            titleFormatJson: titleFormatJson,
            displayTextFormatJson: displayTextFormatJson,
          )
        : null;

    try {
      await widget.repository.updateEntry(
        id: widget.entry.id,
        normalized: widget.entry.isNormalized,
        values: {
          'note_text': noteText.isEmpty ? null : noteText,
          'reference_code': displayCitation.isEmpty ? null : displayCitation,
          'note_format_json': _isBibleItem
              ? overlayJson
              : noteFormatJson,
        },
      );

      final createdFiles = <File>[];
      try {
        await widget.repository.deleteMediaAttachmentsForEntry(widget.entry.id);
        await _deleteMediaFilesForRefs(widget.entry.mediaRefs);
        for (var index = 0; index < _media.length; index++) {
          final attachment = _media[index];
          final persisted = await _persistMediaAttachment(attachment);
          createdFiles.add(File(persisted.absolutePath));
          await widget.repository.addMediaAttachment(
            entryId: widget.entry.id,
            relativePath: persisted.relativePath,
            mimeType: persisted.mimeType,
            fileSize: persisted.fileSize,
            fileHash: persisted.fileHash,
            sortOrder: index,
          );
        }
      } catch (error) {
        for (final file in createdFiles) {
          try {
            if (file.existsSync()) {
              file.deleteSync();
            }
          } catch (_) {
            // Best-effort cleanup.
          }
        }
        rethrow;
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
      _showSnack('Could not save content item.');
    }
  }

  void _toggleFormat(PresentationTextDecorationKind kind) {
    final selection = _noteController.selection;
    if (selection.isCollapsed) {
      _showSnack('Select text first.');
      return;
    }
    final updated = togglePresentationTextDecoration(
      text: _noteController.text,
      current: _noteFormat,
      selection: selection,
      kind: kind,
    );
    if (updated == null) {
      _showSnack('Select text first.');
      return;
    }
    setState(() {
      _noteFormat = updated;
    });
    _noteController.refreshRichText();
  }

  void _toggleDisplayTextFormat(PresentationTextDecorationKind kind) {
    final selection = _displayTextController.selection;
    if (selection.isCollapsed) {
      _showSnack('Select text first.');
      return;
    }
    final updated = togglePresentationTextDecoration(
      text: _displayTextController.text,
      current: _displayTextFormat,
      selection: selection,
      kind: kind,
    );
    if (updated == null) {
      _showSnack('Select text first.');
      return;
    }
    setState(() {
      _displayTextFormat = updated;
    });
    _displayTextController.refreshRichText();
  }

  void _resetDisplayTextToSource() {
    final sourceText = widget.verseText;
    _displayTextController.value = TextEditingValue(
      text: sourceText,
      selection: TextSelection.collapsed(offset: sourceText.length),
      composing: TextRange.empty,
    );
    _displayTextFormat = null;
    _lastDisplayText = sourceText;
    setState(() {});
    _displayTextController.refreshRichText();
  }

  void _toggleTitleFormat(PresentationTextDecorationKind kind) {
    final selection = _titleController.selection;
    if (selection.isCollapsed) {
      _showSnack('Select text first.');
      return;
    }
    final updated = togglePresentationTextDecoration(
      text: _titleController.text,
      current: _titleFormat,
      selection: selection,
      kind: kind,
    );
    if (updated == null) {
      _showSnack('Select text first.');
      return;
    }
    setState(() {
      _titleFormat = updated;
    });
    _titleController.refreshRichText();
  }

  Widget _formatButton(
    IconData icon,
    String label,
    PresentationTextDecorationKind kind,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: _saving ? null : () => _toggleFormat(kind),
        radius: 18,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TagDialogStyles.surfaceHigh(theme),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: TagDialogStyles.outlineColor(theme),
            ),
          ),
          child: Icon(icon, size: 18, color: TagDialogStyles.title(theme)),
        ),
      ),
    );
  }

  Widget _displayFormatButton(
    IconData icon,
    String label,
    PresentationTextDecorationKind kind,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: _saving ? null : () => _toggleDisplayTextFormat(kind),
        radius: 18,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TagDialogStyles.surfaceHigh(theme),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: TagDialogStyles.outlineColor(theme),
            ),
          ),
          child: Icon(icon, size: 18, color: TagDialogStyles.title(theme)),
        ),
      ),
    );
  }

  Widget _titleFormatButton(
    IconData icon,
    String label,
    PresentationTextDecorationKind kind,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: _saving ? null : () => _toggleTitleFormat(kind),
        radius: 18,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TagDialogStyles.surfaceHigh(theme),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: TagDialogStyles.outlineColor(theme),
            ),
          ),
          child: Icon(icon, size: 18, color: TagDialogStyles.title(theme)),
        ),
      ),
    );
  }

  List<PresentationTextSpanRange> _mergePresentationSpans(
    List<PresentationTextSpanRange> spans,
    int textLength,
  ) {
    final normalized = <PresentationTextSpanRange>[];
    for (final span in spans) {
      final start = span.start.clamp(0, textLength).toInt();
      final end = span.end.clamp(0, textLength).toInt();
      if (end <= start) continue;
      normalized.add(span.copyWith(start: start, end: end));
    }
    normalized.sort((a, b) => a.start.compareTo(b.start));
    if (normalized.isEmpty) return normalized;

    final merged = <PresentationTextSpanRange>[normalized.first];
    for (var i = 1; i < normalized.length; i++) {
      final current = normalized[i];
      final last = merged.last;
      if (current.start == last.end &&
          current.style.bold == last.style.bold &&
          current.style.underline == last.style.underline &&
          current.style.italic == last.style.italic) {
        merged[merged.length - 1] = last.copyWith(end: current.end);
        continue;
      }
      merged.add(current);
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = TagDialogStyles.title(theme);
    final bodyColor = TagDialogStyles.body(theme);
    final outlineColor = TagDialogStyles.outlineColor(theme);

    return AlertDialog(
      title: Text(
        widget.title,
        style: TagDialogStyles.titleTextStyle(
          theme,
          widget.fontScale,
          color: titleColor,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isBibleItem) ...[
                Text(
                  'Canonical reference',
                  style: TagDialogStyles.labelTextStyle(
                    theme,
                    widget.fontScale,
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.canonicalReferenceLabel,
                  style: TagDialogStyles.titleTextStyle(
                    theme,
                    widget.fontScale,
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _displayCitationController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Display citation',
                    hintText: 'Daniel 2:46–48, KJV',
                    border: OutlineInputBorder(),
                  ).copyWith(
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    hintStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'User title',
                  style: TagDialogStyles.labelTextStyle(
                    theme,
                    widget.fontScale,
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _titleFormatButton(
                      Icons.format_bold,
                      'Bold selected text',
                      PresentationTextDecorationKind.bold,
                    ),
                    const SizedBox(width: 6),
                    _titleFormatButton(
                      Icons.format_underline,
                      'Underline selected text',
                      PresentationTextDecorationKind.underline,
                    ),
                    const SizedBox(width: 6),
                    _titleFormatButton(
                      Icons.format_italic,
                      'Italic selected text',
                      PresentationTextDecorationKind.italic,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Select text first, then tap B, U, or I.',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: bodyColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  minLines: 1,
                  maxLines: 3,
                  style: _titleBaseStyle(theme),
                  decoration: const InputDecoration(
                    hintText: 'Optional title for this Bible range',
                    border: OutlineInputBorder(),
                  ).copyWith(
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    hintStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Main display text',
                  style: TagDialogStyles.labelTextStyle(
                    theme,
                    widget.fontScale,
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _displayFormatButton(
                      Icons.format_bold,
                      'Bold selected text',
                      PresentationTextDecorationKind.bold,
                    ),
                    const SizedBox(width: 6),
                    _displayFormatButton(
                      Icons.format_underline,
                      'Underline selected text',
                      PresentationTextDecorationKind.underline,
                    ),
                    const SizedBox(width: 6),
                    _displayFormatButton(
                      Icons.format_italic,
                      'Italic selected text',
                      PresentationTextDecorationKind.italic,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Select text first, then tap B, U, or I.',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: bodyColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _displayTextController,
                  minLines: 5,
                  maxLines: 14,
                  style: _displayTextBaseStyle(theme),
                  decoration: const InputDecoration(
                    labelText: 'Display text',
                    hintText:
                        'Edit the visible scripture text for this Bible range',
                    border: OutlineInputBorder(),
                  ).copyWith(
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    hintStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  title: Text(
                    'Source text',
                    style: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    'Read-only Bible DB text for reference',
                    style: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: bodyColor,
                    ),
                  ),
                  children: [
                    if (widget.verseText.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.verseText,
                          style: TagDialogStyles.bodyTextStyle(
                            theme,
                            widget.fontScale,
                            color: TagDialogStyles.title(theme),
                          ),
                        ),
                      )
                    else
                      Text(
                        'Source text unavailable.',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: bodyColor,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'User note / comment',
                  style: TagDialogStyles.labelTextStyle(
                    theme,
                    widget.fontScale,
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _formatButton(
                      Icons.format_bold,
                      'Bold selected text',
                      PresentationTextDecorationKind.bold,
                    ),
                    const SizedBox(width: 6),
                    _formatButton(
                      Icons.format_underline,
                      'Underline selected text',
                      PresentationTextDecorationKind.underline,
                    ),
                    const SizedBox(width: 6),
                    _formatButton(
                      Icons.format_italic,
                      'Italic selected text',
                      PresentationTextDecorationKind.italic,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Select text first, then tap B, U, or I.',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: bodyColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  minLines: 4,
                  maxLines: 10,
                  style: _noteBaseStyle(theme),
                  decoration: const InputDecoration(
                    labelText: 'Note / comment',
                    border: OutlineInputBorder(),
                  ).copyWith(
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    hintStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                    ),
                  ),
                ),
              ] else
                Text(
                  widget.noteLabel,
                  style: TagDialogStyles.titleTextStyle(
                    theme,
                    widget.fontScale,
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 12),
              if (_isBibleItem) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _resetDisplayTextToSource,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(
                      'Reset display text to source',
                      style: TagDialogStyles.buttonTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.accent(theme),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _displayCitationController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: widget.referenceFieldLabel,
                    hintText: widget.referenceFieldHint,
                    border: const OutlineInputBorder(),
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    hintStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _formatButton(
                      Icons.format_bold,
                      'Bold selected text',
                      PresentationTextDecorationKind.bold,
                    ),
                    const SizedBox(width: 6),
                    _formatButton(
                      Icons.format_underline,
                      'Underline selected text',
                      PresentationTextDecorationKind.underline,
                    ),
                    const SizedBox(width: 6),
                    _formatButton(
                      Icons.format_italic,
                      'Italic selected text',
                      PresentationTextDecorationKind.italic,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Select text first, then tap B, U, or I.',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: bodyColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  style: _noteBaseStyle(theme),
                  decoration: InputDecoration(
                    labelText: 'Note / comment',
                    border: const OutlineInputBorder(),
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    hintStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.28,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: outlineColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Media',
                            style: TagDialogStyles.labelTextStyle(
                              theme,
                              widget.fontScale,
                              color: titleColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _saving ? null : _pasteImageFromClipboard,
                          icon: const Icon(Icons.content_paste),
                          label: Text(
                            'Paste Image',
                            style: TagDialogStyles.buttonTextStyle(
                              theme,
                              widget.fontScale,
                              color: TagDialogStyles.accent(theme),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Paste an image from the clipboard. It will be copied into the app media folder.',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: bodyColor,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_media.isEmpty)
                      Text(
                        'No image attached yet.',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: bodyColor,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var index = 0; index < _media.length; index++)
                            _buildMediaTile(_media[index], index),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: Text(
            'Cancel',
            style: TagDialogStyles.buttonTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.body(theme),
            ),
          ),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  _noteController.clear();
                  _noteFormat = null;
                  _lastNoteText = '';
                  setState(() {});
                },
          child: Text(
            'Clear note',
            style: TagDialogStyles.buttonTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.body(theme),
            ),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving ? 'Saving…' : 'Save',
            style: TagDialogStyles.buttonTextStyle(
              theme,
              widget.fontScale,
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _RichNoteController extends TextEditingController {
  _RichNoteController({
    required this.formatResolver,
    required this.baseStyleResolver,
  });

  final PresentationTextFormat? Function() formatResolver;
  final TextStyle Function() baseStyleResolver;

  void refreshRichText() {
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? baseStyleResolver();
    final format = formatResolver();
    final spans = buildPresentationTextSpansFromFormat(
      text: text,
      baseStyle: baseStyle,
      format: format,
    );
    return TextSpan(style: baseStyle, children: spans);
  }
}

class _TextChangeDelta {
  const _TextChangeDelta({
    required this.start,
    required this.oldEnd,
    required this.newEnd,
  });

  final int start;
  final int oldEnd;
  final int newEnd;

  int get insertedLength => newEnd - start;
  int get removedLength => oldEnd - start;
}

class _StagedMediaAttachment {
  const _StagedMediaAttachment({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

class _PersistedMediaAttachment {
  const _PersistedMediaAttachment({
    required this.absolutePath,
    required this.relativePath,
    required this.mimeType,
    required this.fileHash,
    required this.fileSize,
  });

  final String absolutePath;
  final String relativePath;
  final String mimeType;
  final String fileHash;
  final int fileSize;
}
