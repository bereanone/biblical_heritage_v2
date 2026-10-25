import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class PickedNoteImage {
  const PickedNoteImage(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

Future<PickedNoteImage?> pickNoteImage({
  Future<FilePickerResult?> Function()? pick,
}) async {
  final result =
      await (pick?.call() ??
          FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
            dialogTitle: 'Choose Image',
            lockParentWindow: true,
          ));
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes =
      file.bytes ??
      (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null || bytes.isEmpty)
    throw const FormatException('Empty image');
  // Check decodability before staging; preserve the original selected bytes.
  final codec = await ui.instantiateImageCodec(bytes);
  codec.dispose();
  final mime = switch (file.extension?.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    _ => 'image/png',
  };
  return PickedNoteImage(bytes, mime);
}

/// Dialog feedback must live above the note's modal route, never on the page below.
Future<void> showNoteEditorFeedback(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Note editor'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
