import 'dart:async';
import 'package:flutter/material.dart';
import '../data/android_purchase_service.dart';

/// Above the Navigator: expiry cannot be bypassed by an already-open note or
/// reader route. Declining the purchase never deletes or exports saved work.
class AndroidAccessGate extends StatefulWidget {
  const AndroidAccessGate({super.key, required this.child, this.service});
  final Widget child;
  final AndroidPurchaseService? service;
  @override
  State<AndroidAccessGate> createState() => _AndroidAccessGateState();
}

class _AndroidAccessGateState extends State<AndroidAccessGate>
    with WidgetsBindingObserver {
  late final AndroidPurchaseService service;
  Timer? timer;
  bool initialized = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    service = widget.service ?? AndroidPurchaseService.instance;
    service.addListener(changed);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => changed());
    service.initialize().then((_) {
      if (mounted) setState(() => initialized = true);
    });
  }

  void changed() {
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
    timer?.cancel();
    service.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (service.access?.allows(DateTime.now().toUtc()) == true) {
      return widget.child;
    }
    final expired = service.access?.trialEndsAt != null;
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
                        ? 'Purchase permanent access to continue. Your saved study work is preserved.'
                        : 'Try full access free for 14 days. When the trial ends, the app stays locked until you choose to purchase.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'One payment. No subscription or automatic charge.',
                  ),
                  const SizedBox(height: 24),
                  if (!expired)
                    FilledButton(
                      onPressed: !service.busy && service.trialAvailable
                          ? service.startTrial
                          : null,
                      child: const Text('Start 14-day trial — Free'),
                    ),
                  FilledButton(
                    onPressed: !service.busy && service.price != null
                        ? service.purchase
                        : null,
                    child: Text(
                      service.price == null
                          ? 'Permanent unlock unavailable'
                          : 'Purchase permanent access — ${service.price}',
                    ),
                  ),
                  TextButton(
                    onPressed: service.busy
                        ? null
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'The app remains locked. You can purchase whenever you are ready.',
                                ),
                              ),
                            );
                          },
                    child: const Text('Not now'),
                  ),
                  OutlinedButton(
                    onPressed: service.busy ? null : service.restore,
                    child: const Text('Restore Purchases'),
                  ),
                  TextButton(
                    onPressed: service.busy ? null : service.refresh,
                    child: const Text('Try again'),
                  ),
                  if (service.busy)
                    const Center(child: CircularProgressIndicator()),
                  if (service.message != null) Text(service.message!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
