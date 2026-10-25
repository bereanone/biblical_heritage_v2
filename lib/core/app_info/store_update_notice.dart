import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

/// Checks the public store on launch and resume; never blocks offline reading.
/// Only a newer public marketing version prompts, not unreleased build numbers.
class StoreUpdateNotice extends StatefulWidget {
  const StoreUpdateNotice({super.key, required this.child, this.upgrader});

  final Widget child;
  final Upgrader? upgrader;

  @override
  State<StoreUpdateNotice> createState() => _StoreUpdateNoticeState();
}

class _StoreUpdateNoticeState extends State<StoreUpdateNotice> {
  late final Upgrader _upgrader =
      widget.upgrader ??
      _ResilientUpgrader(
        checkOnResume: true,
        durationUntilAlertAgain: const Duration(days: 1),
      );

  @override
  void dispose() {
    _upgrader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return widget.child;
    }
    return UpgradeAlert(
      upgrader: _upgrader,
      showIgnore: false,
      showLater: true,
      showReleaseNotes: false,
      child: widget.child,
    );
  }
}

/// Store outages must not create startup errors or hold up reading.
class _ResilientUpgrader extends Upgrader {
  _ResilientUpgrader({super.checkOnResume, super.durationUntilAlertAgain});

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() async {
    try {
      return await super.updateVersionInfo().timeout(
        const Duration(seconds: 10),
      );
    } catch (_) {
      updateState(state.copyWithNull(versionInfo: null));
      return null;
    }
  }
}
