import 'package:flutter/widgets.dart';

import 'core/bootstrap/bootstrap_gate.dart';
import 'core/bootstrap/sandbox_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final showSetupScreen = await SandboxBootstrap.needsInteractiveBootstrap();
  runApp(BootstrapGate(showSetupScreen: showSetupScreen));
}
