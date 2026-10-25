import 'package:flutter/material.dart';
import '../data/ministry_enrollment_service.dart';
import 'ministry_setup_screen.dart';

class MinistryEnrollmentGate extends StatefulWidget {
  const MinistryEnrollmentGate({
    super.key,
    required this.service,
    required this.child,
  });
  final MinistryEnrollmentService service;
  final Widget child;
  @override
  State<MinistryEnrollmentGate> createState() => _MinistryEnrollmentGateState();
}

class _MinistryEnrollmentGateState extends State<MinistryEnrollmentGate> {
  late Future<void> _loading;
  @override
  void initState() {
    super.initState();
    _loading = _initialize();
  }

  Future<void> _initialize() async {
    await widget.service.initialize();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _loading,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Your saved setup could not be loaded.'),
                TextButton(
                  onPressed: () => setState(() => _loading = _initialize()),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return ValueListenableBuilder(
        valueListenable: widget.service.state,
        builder: (context, enrollment, _) => enrollment?.setupCompleted == true
            ? widget.child
            : MinistrySetupScreen(service: widget.service, onCompleted: () {}),
      );
    },
  );
}
