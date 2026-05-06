import 'package:flutter/material.dart';

import '../../app/study_bible_app.dart';
import 'startup_coordinator.dart';

class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key});

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  StartupSnapshot? _snapshot;
  String _status = 'Preparing sandbox...';
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final snapshot = await StartupCoordinator.instance.initialize();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _status = snapshot.message;
        _error = snapshot.errorMessage;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _snapshot = StartupSnapshot(
          phase: StartupPhase.migrationFailed,
          message: 'Startup failed.',
          errorMessage: error.toString(),
        );
        _status = 'Startup failed.';
        _error = error;
        _busy = false;
      });
    }
  }

  Future<void> _runSelection(Future<StartupSnapshot> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await action();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _status = snapshot.message;
        _error = snapshot.errorMessage;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _snapshot = StartupSnapshot(
          phase: StartupPhase.migrationFailed,
          message: 'Migration failed.',
          errorMessage: error.toString(),
        );
        _status = 'Migration failed.';
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null || _busy) {
      return _BootstrapSplash(status: _status);
    }

    if (snapshot.isReady ||
        snapshot.phase == StartupPhase.noLegacyFound ||
        snapshot.phase == StartupPhase.freshInstallSelected ||
        snapshot.phase == StartupPhase.migrationCompleted) {
      return const StudyBibleApp();
    }

    if (snapshot.requiresDecision) {
      return _LegacyUpgradeDecisionScreen(
        status: snapshot.message,
        errorMessage: _error?.toString() ?? snapshot.errorMessage,
        onUpgrade: () =>
            _runSelection(StartupCoordinator.instance.backUpAndUpgrade),
        onFreshStart: () => _runSelection(
          StartupCoordinator.instance.startFreshButKeepLegacyBackup,
        ),
        onNotNow: () {},
      );
    }

    return _BootstrapError(
      error: _error ?? snapshot.errorMessage ?? snapshot.message,
      onRetry: _initialize,
    );
  }
}

class _BootstrapSplash extends StatelessWidget {
  const _BootstrapSplash({required this.status});

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

class _LegacyUpgradeDecisionScreen extends StatelessWidget {
  const _LegacyUpgradeDecisionScreen({
    required this.status,
    required this.onUpgrade,
    required this.onFreshStart,
    required this.onNotNow,
    this.errorMessage,
  });

  final String status;
  final String? errorMessage;
  final VoidCallback onUpgrade;
  final VoidCallback onFreshStart;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Legacy data found',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(status),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        'Choose whether to back up and upgrade existing data or start fresh while keeping a legacy backup.',
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton(
                            onPressed: onUpgrade,
                            child: const Text(
                              'Back Up and Upgrade Existing Data',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: onFreshStart,
                            child: const Text(
                              'Start Fresh but Keep Legacy Backup',
                            ),
                          ),
                          TextButton(
                            onPressed: onNotNow,
                            child: const Text('Cancel / Not Now'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapError extends StatelessWidget {
  const _BootstrapError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

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
                    child: SelectableText(
                      error?.toString() ?? '(unknown error)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
