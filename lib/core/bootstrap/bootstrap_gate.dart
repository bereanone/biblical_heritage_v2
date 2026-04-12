import 'package:flutter/material.dart';

import '../../app/study_bible_app.dart';
import 'sandbox_bootstrap.dart';

class BootstrapGate extends StatefulWidget {
  const BootstrapGate({
    super.key,
    required this.showSetupScreen,
  });

  final bool showSetupScreen;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  late final Future<void> _future;
  String _status = 'Preparing sandbox...';

  @override
  void initState() {
    super.initState();
    _future = SandboxBootstrap.ensureReady(
      onStatus: (status) {
        if (!mounted) return;
        setState(() {
          _status = status;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return _BootstrapError(error: snapshot.error);
          }
          return const StudyBibleApp();
        }

        if (!widget.showSetupScreen) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return _BootstrapSplash(status: _status);
      },
    );
  }
}

class _BootstrapSplash extends StatelessWidget {
  const _BootstrapSplash({
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Preparing StudyBible…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapError extends StatelessWidget {
  const _BootstrapError({
    required this.error,
  });

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Startup failed',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The app could not initialize its database sandbox.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(error?.toString() ?? '(unknown error)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
