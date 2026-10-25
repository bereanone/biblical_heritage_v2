import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';
import 'ministry_profile.dart';

typedef MinistrySeedWriter = Future<void> Function(MinistryProfile profile);

class MinistryEnrollmentService {
  MinistryEnrollmentService({
    required this.read,
    required this.write,
    required this.seed,
    DateTime Function()? now,
    Future<Map<String, Object?>> Function()? loadInstallState,
    Future<void> Function(Map<String, Object?>)? saveInstallState,
  }) : now = now ?? DateTime.now,
       loadInstallState = loadInstallState ?? LocalSettingsStore.instance.load,
       saveInstallState = saveInstallState ?? LocalSettingsStore.instance.save;

  static const settingKey = 'partners.enrollment.v1';
  static final instance = MinistryEnrollmentService(
    read: () => AppSettingsService.instance.loadRawSetting(settingKey),
    write: (value) =>
        AppSettingsService.instance.saveRawSetting(settingKey, value),
    seed: (profile) => HashTagRepository().ensureMinistryStarterTags(
      folder: profile.folder!,
      tags: profile.starterTags,
    ),
  );

  final Future<String?> Function() read;
  final Future<void> Function(String value) write;
  final MinistrySeedWriter seed;
  final DateTime Function() now;
  final Future<Map<String, Object?>> Function() loadInstallState;
  final Future<void> Function(Map<String, Object?>) saveInstallState;
  final state = ValueNotifier<MinistryEnrollment?>(null);
  Future<void>? _pending;
  bool _existingInstallBeforeBootstrap = false;
  bool _installCaptured = false;

  /// Must run before bootstrap creates a device identity for a fresh install.
  Future<void> captureInstallBeforeBootstrap() async {
    if (_installCaptured) return;
    final local = await loadInstallState();
    const originKey = 'partners.install_origin.v1';
    final origin = local[originKey];
    if (origin != null && origin != 'new' && origin != 'existing') {
      throw const FormatException('Cannot read saved installation origin.');
    }
    _existingInstallBeforeBootstrap =
        origin == 'existing' ||
        (origin == null &&
            ((local['device_id']?.toString().isNotEmpty ?? false) ||
                local.containsKey('startup_reviewed_version')));
    if (origin == null) {
      local[originKey] = _existingInstallBeforeBootstrap ? 'existing' : 'new';
      await saveInstallState(local);
    }
    _installCaptured = true;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final previous = _pending;
    final result = previous == null ? action() : previous.then((_) => action());
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<MinistryEnrollment> initialize({bool? existingInstall}) => _serialize(
    () async {
      final saved = await read();
      final MinistryEnrollment enrollment;
      if (saved != null) {
        // Unknown brands survive updates; never silently reset setup or rights.
        enrollment = MinistryEnrollment.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      } else {
        final legacy = existingInstall ?? _existingInstallBeforeBootstrap;
        enrollment = MinistryEnrollment(
          ministryId: MinistryProfile.biblicalHeritage.id,
          setupCompleted: legacy,
          grandfathered: legacy,
          firstSeenUtc: now().toUtc(),
        );
        await write(jsonEncode(enrollment.toJson()));
      }
      if (enrollment.setupCompleted && enrollment.profile?.folder != null) {
        await seed(enrollment.profile!);
      }
      state.value = enrollment;
      return enrollment;
    },
  );

  Future<MinistryEnrollment> select(MinistryProfile profile) => _serialize(
    () async {
      final current = state.value;
      if (current == null) throw StateError('Ministry setup is not loaded.');
      if (profile.folder != null) await seed(profile);
      final updated = current.select(profile);
      // Persist before notifying the welcome screen. Failure leaves setup open.
      await write(jsonEncode(updated.toJson()));
      state.value = updated;
      return updated;
    },
  );
}
