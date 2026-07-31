import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/study_bible_app.dart';
import '../../features/utilities/presentation/library_root_setup_screen.dart';
import '../../features/library/presentation/library_access_required_screen.dart';
import 'library_root_native.dart';
import 'library_root_service.dart';
import 'sandbox_bootstrap.dart';
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
  bool _bootstrapStarted = false;
  bool _launchBibleOnly = false;
  bool _showAdvancedDiagnostics = false;
  bool _startupTakingLong = false;
  int _bootstrapAttempt = 0;
  Object? _error;
  String? _errorType;
  String? _lastStep;
  Future<StartupDiagnostics>? _diagnosticsFuture;
  Timer? _startupWatchdog;
  bool _libraryAuthorizationRequired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bootstrapStarted) return;
      _initialize();
    });
  }

  @override
  void dispose() {
    _startupWatchdog?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final attempt = ++_bootstrapAttempt;
    _bootstrapStarted = true;
    _startupWatchdog?.cancel();
    _startupTakingLong = false;
    if (mounted) {
      setState(() {
        _busy = true;
        _status = 'Loading startup state...';
        _lastStep = _status;
        _error = null;
        _errorType = null;
        _diagnosticsFuture = null;
        _showAdvancedDiagnostics = false;
      });
    }
    _startupWatchdog = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_busy || _snapshot != null) return;
      setState(() {
        _startupTakingLong = true;
        _status = 'Still starting... Last step: ${_lastStep ?? _status}';
      });
    });
    try {
      if (LibraryRootNative.usesAndroidDocumentTree) {
        _updateStatus('Validating library folder authorization...');
        final authorization = await LibraryRootService.instance
            .validateAndroidAuthorization(refresh: true);
        if (!authorization.isAuthorized) {
          _startupWatchdog?.cancel();
          if (!mounted || attempt != _bootstrapAttempt) return;
          setState(() {
            _libraryAuthorizationRequired = true;
            _busy = false;
            _status = 'Library access required.';
            _lastStep = 'Android library authorization validation';
          });
          return;
        }
      }
      final snapshot = await StartupCoordinator.instance.initialize(
        onStatus: _updateStatus,
      );
      _startupWatchdog?.cancel();
      if (!mounted || attempt != _bootstrapAttempt) return;
      setState(() {
        _snapshot = snapshot;
        _status = snapshot.message;
        _lastStep = snapshot.message;
        _error = snapshot.errorMessage;
        _errorType = null;
        _busy = false;
        _startupTakingLong = false;
      });
    } catch (error) {
      _startupWatchdog?.cancel();
      if (!mounted || attempt != _bootstrapAttempt) return;
      setState(() {
        _snapshot = StartupSnapshot(
          phase: StartupPhase.migrationFailed,
          message: error is TimeoutException
              ? 'Startup timed out.'
              : 'Startup failed.',
          errorMessage: error.toString(),
        );
        _status = error is TimeoutException
            ? 'Startup timed out.'
            : 'Startup failed.';
        _error = error;
        _errorType = error.runtimeType.toString();
        _lastStep = _status;
        _busy = false;
        _startupTakingLong = false;
        _diagnosticsFuture = null;
        _showAdvancedDiagnostics = false;
      });
    }
  }

  Future<void> _runSelection(Future<StartupSnapshot> Function() action) async {
    setState(() {
      _busy = true;
      _status = 'Running startup selection...';
      _lastStep = _status;
      _error = null;
      _errorType = null;
      _diagnosticsFuture = null;
      _showAdvancedDiagnostics = false;
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
        _errorType = error.runtimeType.toString();
        _lastStep = _status;
        _busy = false;
        _diagnosticsFuture = null;
        _showAdvancedDiagnostics = false;
      });
    }
  }

  void _updateStatus(String status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _lastStep = status;
      if (_startupTakingLong) {
        _status = 'Still starting... Last step: $status';
      }
    });
  }

  Future<void> _retryStartup() async {
    if (!mounted) return;
    setState(() {
      _launchBibleOnly = false;
    });
    await _initialize();
  }

  void _resumeAfterLibraryReconnect() {
    if (!mounted) return;
    setState(() {
      _libraryAuthorizationRequired = false;
      _snapshot = null;
    });
    _initialize();
  }

  Future<void> _continueToBibleOnly() async {
    if (!mounted) return;
    _startupWatchdog?.cancel();
    setState(() {
      _launchBibleOnly = true;
      _busy = false;
      _startupTakingLong = false;
    });
  }

  Future<void> _disableELibraryForThisLaunch() async {
    if (!mounted) return;
    _startupWatchdog?.cancel();
    setState(() {
      _status = 'Starting Bible only with eLibrary disabled for this launch...';
      _launchBibleOnly = true;
      _busy = false;
      _startupTakingLong = false;
    });
  }

  Future<void> _openLibraryRootSetup() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LibraryRootSetupScreen()),
    );
  }

  Future<void> _toggleAdvancedDiagnostics() async {
    if (!mounted) return;
    setState(() {
      _showAdvancedDiagnostics = !_showAdvancedDiagnostics;
    });
    if (_showAdvancedDiagnostics) {
      _diagnosticsFuture = StartupDiagnostics.capture(
        error: _error,
        errorType: _errorType,
        lastStep: _lastStep ?? _status,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_libraryAuthorizationRequired) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: LibraryAccessRequiredScreen(
          onAccessRestored: _resumeAfterLibraryReconnect,
        ),
      );
    }
    if (_launchBibleOnly) {
      return const StudyBibleApp();
    }

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
        onNotNow: _continueToBibleOnly,
      );
    }

    return _StartupRecoveryScreen(
      error: _error ?? snapshot.errorMessage ?? snapshot.message,
      errorType: _errorType,
      lastStep: _lastStep ?? snapshot.message,
      onRetry: _retryStartup,
      onBibleOnly: _continueToBibleOnly,
      onDisableELibrary: _disableELibraryForThisLaunch,
      onReselectLibraryRoot: _openLibraryRootSetup,
      onToggleDiagnostics: _toggleAdvancedDiagnostics,
      showDiagnostics: _showAdvancedDiagnostics,
      diagnosticsFuture: _diagnosticsFuture,
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
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'StudyBible2',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: Colors.amberAccent,
                            strokeWidth: 4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Starting Biblical Heritage...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
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
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  elevation: 0,
                  color: const Color(0xFF151515),
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
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          status,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          'Choose whether to back up and upgrade existing data or continue into the Bible without changing files.',
                          style: TextStyle(color: Colors.white70),
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
                              child: const Text('Continue to Bible Only'),
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
      ),
    );
  }
}

class _StartupRecoveryScreen extends StatelessWidget {
  const _StartupRecoveryScreen({
    required this.error,
    required this.onRetry,
    required this.onBibleOnly,
    required this.onDisableELibrary,
    required this.onReselectLibraryRoot,
    required this.onToggleDiagnostics,
    required this.lastStep,
    required this.showDiagnostics,
    this.diagnosticsFuture,
    this.errorType,
  });

  final Object? error;
  final String? errorType;
  final String lastStep;
  final VoidCallback onRetry;
  final VoidCallback onBibleOnly;
  final VoidCallback onDisableELibrary;
  final VoidCallback onReselectLibraryRoot;
  final VoidCallback onToggleDiagnostics;
  final bool showDiagnostics;
  final Future<StartupDiagnostics>? diagnosticsFuture;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Card(
                  elevation: 0,
                  color: const Color(0xFF151515),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Biblical Heritage could not finish startup.',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'You can continue into the Bible, retry startup, or open Library Root Setup without deleting anything.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        _ErrorField(
                          label: 'Error type',
                          value: errorType ?? error.runtimeType.toString(),
                        ),
                        const SizedBox(height: 10),
                        _ErrorField(
                          label: 'Message',
                          value: error?.toString() ?? '(unknown error)',
                        ),
                        const SizedBox(height: 10),
                        _ErrorField(
                          label: 'Last startup step',
                          value: lastStep,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: onBibleOnly,
                              child: const Text('Continue to Bible Only'),
                            ),
                            OutlinedButton(
                              onPressed: onDisableELibrary,
                              child: const Text(
                                'Disable eLibrary for This Launch',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: onRetry,
                              child: const Text('Retry Startup'),
                            ),
                            OutlinedButton(
                              onPressed: onReselectLibraryRoot,
                              child: const Text('Reselect Library Root'),
                            ),
                            TextButton(
                              onPressed: onToggleDiagnostics,
                              child: Text(
                                showDiagnostics
                                    ? 'Hide Advanced Diagnostics'
                                    : 'Advanced Diagnostics',
                              ),
                            ),
                          ],
                        ),
                        if (showDiagnostics) ...[
                          const SizedBox(height: 20),
                          _DiagnosticsPanel(future: diagnosticsFuture),
                        ],
                      ],
                    ),
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

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({required this.future});

  final Future<StartupDiagnostics>? future;

  @override
  Widget build(BuildContext context) {
    final diagnosticsFuture = future;
    if (diagnosticsFuture == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<StartupDiagnostics>(
      future: diagnosticsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final diagnostics = snapshot.data!;
        final lines = <String>[
          'App support path: ${diagnostics.appSupportPath}',
          'App documents path: ${diagnostics.appDocumentsPath}',
          'Library root path: ${diagnostics.libraryRootPath ?? '(none)'}',
          'Database path: ${diagnostics.databasePath}',
          'user.db exists: ${diagnostics.userDbExists ? 'yes' : 'no'}',
          'ePubs/EGW exists: ${diagnostics.egwFolderExists ? 'yes' : 'no'}',
          'Last error category: ${diagnostics.errorCategory}',
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Advanced Diagnostics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            for (final line in lines) ...[
              _ErrorField(label: '', value: line),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class StartupDiagnostics {
  const StartupDiagnostics({
    required this.appSupportPath,
    required this.appDocumentsPath,
    required this.libraryRootPath,
    required this.databasePath,
    required this.userDbExists,
    required this.egwFolderExists,
    required this.errorCategory,
  });

  final String appSupportPath;
  final String appDocumentsPath;
  final String? libraryRootPath;
  final String databasePath;
  final bool userDbExists;
  final bool egwFolderExists;
  final String errorCategory;

  static Future<StartupDiagnostics> capture({
    Object? error,
    String? errorType,
    String? lastStep,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final documentsDir = await getApplicationDocumentsDirectory();
    final librarySelection = await LibraryRootService.instance.loadSelection();
    final databasePath = await SandboxBootstrap.userDatabasePath();
    final userDbExists = await File(databasePath).exists();
    final rootPath = librarySelection.path?.trim();
    var egwFolderExists = false;
    if (rootPath != null && rootPath.isNotEmpty) {
      final epubEgw = Directory(p.join(rootPath, 'ePubs', 'EGW'));
      final pdfEgw = Directory(p.join(rootPath, 'PDFs', 'EGW'));
      egwFolderExists = await epubEgw.exists() || await pdfEgw.exists();
    }
    return StartupDiagnostics(
      appSupportPath: supportDir.path,
      appDocumentsPath: documentsDir.path,
      libraryRootPath: rootPath?.isEmpty == true ? null : rootPath,
      databasePath: databasePath,
      userDbExists: userDbExists,
      egwFolderExists: egwFolderExists,
      errorCategory: _categorizeError(
        error: error,
        errorType: errorType,
        lastStep: lastStep,
      ),
    );
  }

  static String _categorizeError({
    required Object? error,
    required String? errorType,
    required String? lastStep,
  }) {
    final type = (errorType ?? error.runtimeType.toString()).toLowerCase();
    final message = '${error ?? ''} ${lastStep ?? ''}'.toLowerCase();
    if (type.contains('timeout') || message.contains('timeout')) {
      return 'startup timeout';
    }
    if (message.contains('database') || message.contains('db')) {
      return 'database';
    }
    if (message.contains('root')) {
      return 'library root';
    }
    if (message.contains('elibrary') ||
        message.contains('catalog') ||
        message.contains('index') ||
        message.contains('download')) {
      return 'eLibrary/catalog';
    }
    return 'bootstrap';
  }
}

class _ErrorField extends StatelessWidget {
  const _ErrorField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF151515),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.amberAccent,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
