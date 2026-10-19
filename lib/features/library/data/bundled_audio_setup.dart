import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'bundled_audio_installer.dart';
import 'verified_audio_download.dart';
import 'optional_book_companions.dart';

class BundledAudioSetup extends ChangeNotifier {
  BundledAudioSetup._();
  @visibleForTesting
  BundledAudioSetup.forTesting({
    required Future<Map<String, dynamic>> Function() loadManifest,
    required Future<void> Function(Map<String, dynamic>) install,
    Future<bool> Function(Map<String, dynamic>)? verifyInstalled,
  }) : _testManifest = loadManifest,
       _testInstall = install,
       _testReady = verifyInstalled;
  Future<Map<String, dynamic>> Function()? _testManifest;
  Future<void> Function(Map<String, dynamic>)? _testInstall;
  Future<bool> Function(Map<String, dynamic>)? _testReady;
  final Set<String> _verifiedPackages = {};

  static final instance = BundledAudioSetup._();
  bool running = false;
  bool showProgress = false;
  bool complete = false;
  DateTime? completedAt;
  String message = 'Preparing included recordings…';
  String? error;
  double? progress;
  Future<void>? _pending;

  final Set<String> _sources = {};
  Set<String> _completedSources = {};
  Future<void> ensure({Set<String>? sourceHashes}) {
    // A loading/filtering catalog is not removal of installed companions.
    // Only a newly recognized optional source changes the download request.
    if (sourceHashes != null) {
      _sources.addAll(sourceHashes.where(OptionalBookCompanions.matchesWor));
    }
    if (!setEquals(_sources, _completedSources)) complete = false;
    if ((!Platform.isAndroid && _testInstall == null) || complete) {
      return Future.value();
    }
    return _pending ??= _run().whenComplete(() {
      _pending = null;
      if (error == null && !complete) ensure();
    });
  }

  Future<void> _run() async {
    running = true;
    showProgress = false;
    completedAt = null;
    error = null;
    notifyListeners();
    final downloader = VerifiedAudioDownload();
    try {
      final requestedSources = Set<String>.of(_sources);
      final manifest = _testManifest != null
          ? await _testManifest!()
          : jsonDecode(
                  await rootBundle.loadString(
                    'assets/bundled_library/audio.json',
                  ),
                )
                as Map<String, dynamic>;
      final packages = (manifest['packages'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      if (packages.where((p) => p['requires_source_sha256'] == null).length !=
              6 ||
          packages.any((p) => p['url'] == null)) {
        throw const FormatException(
          'Recording download manifest is incomplete',
        );
      }
      packages.removeWhere(
        (p) =>
            p['requires_source_sha256'] != null &&
            !requestedSources.contains(p['requires_source_sha256']),
      );
      final docs = _testInstall == null
          ? await getApplicationDocumentsDirectory()
          : Directory.systemTemp;
      final installer = BundledAudioInstaller(
        Directory('${docs.path}/elibrary_audio'),
        downloader,
      );
      for (var i = 0; i < packages.length; i++) {
        final package = packages[i];
        final packageKey = '${package['id']}:${package['sha256']}';
        if (_verifiedPackages.contains(packageKey)) continue;
        final ready = _testReady != null
            ? await _testReady!(package)
            : _testInstall == null && await installer.verifyInstalled(package);
        if (ready) {
          _verifiedPackages.add(packageKey);
          continue;
        }
        showProgress = true;
        message =
            'Preparing ${package['title']} (${i + 1} of ${packages.length})';
        progress = null;
        notifyListeners();
        var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
        if (_testInstall != null) {
          await _testInstall!(package);
        } else {
          await installer.install(
            package,
            onProgress: (received, total) {
              final now = DateTime.now();
              if (received != total &&
                  now.difference(lastUpdate).inMilliseconds < 250) {
                return;
              }
              lastUpdate = now;
              progress = (i + received / total) / packages.length;
              message = received == total
                  ? 'Checking and installing ${package['title']}…'
                  : 'Downloading ${package['title']} (${i + 1} of ${packages.length})';
              notifyListeners();
            },
          );
        }
        _verifiedPackages.add(packageKey);
      }
      _completedSources = requestedSources;
      complete = setEquals(_sources, requestedSources);
      completedAt = complete && showProgress ? DateTime.now() : null;
      progress = 1;
      message = 'Included recordings are ready.';
    } catch (e, stack) {
      debugPrint('Included audio setup: $e\n$stack');
      error =
          'Recordings are not fully installed. Check your connection and '
          'available storage, then retry. Completed downloads are kept.';
      message = 'Included recordings need attention';
    } finally {
      downloader.close();
      running = false;
      notifyListeners();
    }
  }
}
