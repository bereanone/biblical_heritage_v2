import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'core/bootstrap/bootstrap_gate.dart';

Future<void> main() async {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
      };
      ui.PlatformDispatcher.instance.onError = (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
        return true;
      };
      runApp(const BootstrapGate());
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, message) {
        if (message.contains('*** sqflite warning ***') ||
            message.contains('You are changing sqflite default factory.')) {
          return;
        }
        parent.print(zone, message);
      },
    ),
  );
}
