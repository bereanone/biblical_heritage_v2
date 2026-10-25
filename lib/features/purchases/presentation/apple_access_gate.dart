import 'dart:async';
import 'package:flutter/material.dart';
import '../../partners/data/ministry_enrollment_service.dart';
import '../../partners/presentation/ministry_setup_screen.dart';
import '../data/apple_purchase_service.dart';

/// Lives above the Navigator, so previously opened reader routes cannot bypass
/// trial expiry. StoreKit, not ministry codes, decides purchase ownership.
class AppleAccessGate extends StatefulWidget {
  const AppleAccessGate({super.key, required this.child, this.service});
  final Widget child;
  final ApplePurchaseService? service;
  @override
  State<AppleAccessGate> createState() => _AppleAccessGateState();
}

class _AppleAccessGateState extends State<AppleAccessGate>
    with WidgetsBindingObserver {
  late final ApplePurchaseService service;
  Timer? _clock;
  bool initialized = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    service = widget.service ?? ApplePurchaseService.instance;
    service.addListener(_changed);
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => _changed());
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final enrollment = await MinistryEnrollmentService.instance.initialize();
      await service.initialize(existingCustomer: enrollment.grandfathered);
    } catch (_) {
      service.message =
          'Your saved access could not be loaded. Please try again.';
    }
    if (mounted) setState(() => initialized = true);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && initialized) {
      unawaited(service.refresh());
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    service.removeListener(_changed);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (MinistryEnrollmentService.instance.state.value?.setupCompleted !=
        true) {
      return MinistrySetupScreen(
        service: MinistryEnrollmentService.instance,
        onCompleted: _changed,
      );
    }
    if (service.access?.allows(DateTime.now().toUtc()) == true) {
      return widget.child;
    }
    final expired = service.access?.trialStarted == true;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    expired
                        ? 'Your 14-day trial has ended'
                        : 'Welcome to StudyBible',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    expired
                        ? 'Unlock full access to continue. Your saved study work is preserved.'
                        : 'Try full access free for 14 days. After the trial, access stops until you choose to purchase. There is no automatic charge.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A permanent unlock is a one-time purchase with no subscription. Eligible Apple family members can share it.',
                  ),
                  const SizedBox(height: 24),
                  if (!expired)
                    FilledButton(
                      onPressed: !service.busy && service.trialAvailable
                          ? () => service.purchase(trial: true)
                          : null,
                      child: const Text('Start 14-day Trial — Free'),
                    ),
                  FilledButton(
                    onPressed: !service.busy && service.price != null
                        ? () => service.purchase()
                        : null,
                    child: Text(
                      service.price == null
                          ? 'Permanent unlock unavailable'
                          : 'Permanent unlock — ${service.price}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: service.busy ? null : service.restore,
                    child: const Text('Restore Purchases'),
                  ),
                  TextButton(
                    onPressed: service.busy ? null : service.redeem,
                    child: const Text('Redeem offer or gift code'),
                  ),
                  TextButton(
                    onPressed: service.busy ? null : service.refresh,
                    child: const Text('Check access again'),
                  ),
                  if (service.busy)
                    const Center(child: CircularProgressIndicator()),
                  if (service.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(service.message!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
