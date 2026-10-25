import 'package:flutter/material.dart';
import '../data/ministry_enrollment_service.dart';
import '../data/ministry_profile.dart';

class MinistrySetupScreen extends StatefulWidget {
  const MinistrySetupScreen({
    super.key,
    required this.service,
    required this.onCompleted,
    this.initialSetup = true,
  });
  final MinistryEnrollmentService service;
  final VoidCallback onCompleted;
  final bool initialSetup;

  @override
  State<MinistrySetupScreen> createState() => _MinistrySetupScreenState();
}

class _MinistrySetupScreenState extends State<MinistrySetupScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply({bool withoutCode = false}) async {
    if (_busy) return;
    final profile = withoutCode
        ? MinistryProfile.biblicalHeritage
        : MinistryProfile.forCode(_code.text);
    if (profile == null) {
      setState(
        () => _error =
            'That promotional code is not available. Check the code supplied by your ministry.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.select(profile);
      if (mounted) widget.onCompleted();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Setup could not be saved. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.initialSetup && !_busy,
    child: Scaffold(
      appBar: widget.initialSetup
          ? null
          : AppBar(title: const Text('Ministry branding')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.initialSetup
                        ? 'Preparing to install #StudyBible'
                        : 'Choose your ministry branding',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please enter your promotional code, or continue without one to use Biblical Heritage.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Promotional code',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      errorMaxLines: 4,
                    ),
                    onSubmitted: (_) => _apply(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : () => _apply(),
                    child: Text(_busy ? 'Saving…' : 'Apply promotional code'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _apply(withoutCode: true),
                    child: Text(
                      widget.initialSetup
                          ? 'Install without promotional code'
                          : 'Use Biblical Heritage branding',
                    ),
                  ),
                  if (widget.service.state.value?.grandfathered == true) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'As an early customer, you keep full access. Changing ministry branding does not require another purchase.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
