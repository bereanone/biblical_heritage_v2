import 'package:flutter/widgets.dart';

import 'core/bootstrap/bootstrap_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapGate());
}
