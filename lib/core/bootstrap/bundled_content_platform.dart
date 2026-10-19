import 'package:flutter/foundation.dart';

/// Managed mobile content uses the app sandbox. Desktop libraries retain their
/// separately selected roots and must not be modified by mobile provisioning.
bool supportsBundledContent(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

bool get bundledContentEnabled =>
    !kIsWeb && supportsBundledContent(defaultTargetPlatform);
