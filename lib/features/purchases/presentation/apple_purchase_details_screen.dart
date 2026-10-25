import 'package:flutter/material.dart';
import '../data/apple_purchase_service.dart';

class ApplePurchaseDetailsScreen extends StatefulWidget {
  const ApplePurchaseDetailsScreen({super.key});
  @override
  State<ApplePurchaseDetailsScreen> createState() =>
      _ApplePurchaseDetailsScreenState();
}

class _ApplePurchaseDetailsScreenState
    extends State<ApplePurchaseDetailsScreen> {
  final service = ApplePurchaseService.instance;
  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
    service.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    service.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = service.access;
    final permanent = access?.paid == true || access?.legacy == true;
    return Scaffold(
      appBar: AppBar(title: const Text('StudyBible access')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            access?.legacy == true
                ? 'Permanent access — early customer'
                : access?.paid == true
                ? 'Permanent access — includes eligible Family Sharing'
                : '14-day trial access',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (permanent)
            const Text(
              'You already have full access. You do not need to purchase again.',
            ),
          if (!permanent && service.price != null)
            FilledButton(
              onPressed: service.busy ? null : () => service.purchase(),
              child: Text('Permanent unlock — ${service.price}'),
            ),
          OutlinedButton(
            onPressed: service.busy ? null : service.restore,
            child: const Text('Restore Purchases'),
          ),
          TextButton(
            onPressed: service.busy ? null : service.redeem,
            child: const Text('Redeem offer or gift code'),
          ),
          if (service.busy) const Center(child: CircularProgressIndicator()),
          if (service.message != null) Text(service.message!),
        ],
      ),
    );
  }
}
