import 'package:flutter/material.dart';

import '../../../core/bootstrap/library_root_service.dart';

class LibraryAccessRequiredScreen extends StatefulWidget {
  const LibraryAccessRequiredScreen({super.key, this.onAccessRestored});

  final VoidCallback? onAccessRestored;

  @override
  State<LibraryAccessRequiredScreen> createState() =>
      _LibraryAccessRequiredScreenState();
}

class _LibraryAccessRequiredScreenState
    extends State<LibraryAccessRequiredScreen> {
  bool _working = false;
  String? _error;

  Future<void> _reconnect() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final authorization = await LibraryRootService.instance
          .reconnectAndroidLibraryRoot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Library access restored. ${authorization.fileCount} existing '
            'files recognized; no download was started.',
          ),
        ),
      );
      final onAccessRestored = widget.onAccessRestored;
      if (onAccessRestored != null) {
        onAccessRestored();
      } else {
        Navigator.of(context).pop(true);
      }
    } on LibraryRootAuthorizationMissing catch (error) {
      if (!mounted) return;
      setState(() => _error = error.detail ?? error.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Library Access Required')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.folder_shared_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'StudyBible found or expects an existing library folder, '
                      'but Android requires you to grant access to it again.',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your books have not been deleted.\n\n'
                      'In the Android folder picker, open Documents and select '
                      'the existing StudyBible folder itself. Do not select the '
                      'Documents folder.',
                      textAlign: TextAlign.center,
                    ),
                    if (_working) ...[
                      const SizedBox(height: 24),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text(
                        'Verifying access and recognizing existing files…',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: _working ? null : _reconnect,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Reconnect Existing StudyBible Folder'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
