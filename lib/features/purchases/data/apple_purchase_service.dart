import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// This release switch stays off until StoreKit sandbox acceptance is complete.
/// Android's Play billing is a separate implementation; never gate it on Apple.
const applePurchasesEnabled = bool.fromEnvironment('STUDYBIBLE_APPLE_BILLING');

class AppleAccess {
  const AppleAccess({
    required this.paid,
    required this.legacy,
    required this.trialStarted,
    required this.checkedAt,
    this.trialEndsAt,
  });
  final bool paid, legacy, trialStarted;
  final DateTime checkedAt;
  final DateTime? trialEndsAt;
  bool allows(DateTime now) =>
      paid ||
      legacy ||
      (trialEndsAt != null &&
          (now.isAfter(checkedAt) ? now : checkedAt).isBefore(trialEndsAt!));
  factory AppleAccess.fromMap(Map<Object?, Object?> map) => AppleAccess(
    paid: map['paid'] == true,
    legacy: map['legacy'] == true,
    trialStarted: map['trialStarted'] == true,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['checkedAt'] as num).round(),
      isUtc: true,
    ),
    trialEndsAt: map['trialEndsAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (map['trialEndsAt'] as num).round(),
            isUtc: true,
          )
        : null,
  );
}

class ApplePurchaseService extends ChangeNotifier {
  ApplePurchaseService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('studybible/purchases') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'accessChanged') {
        access = AppleAccess.fromMap(
          Map<Object?, Object?>.from(call.arguments as Map),
        );
        notifyListeners();
      }
    });
  }
  static final instance = ApplePurchaseService();
  static const unlockId = 'studybible_full_access';
  static const trialId = 'studybible_trial_14_days';
  final MethodChannel _channel;
  AppleAccess? access;
  String? price;
  bool trialAvailable = false;
  bool busy = false;
  String? message;
  Future<void> initialize({required bool existingCustomer}) async {
    await _run(() async {
      _accept(
        await _channel.invokeMapMethod<Object?, Object?>('initialize', {
          'existingCustomer': existingCustomer,
        }),
      );
      await _products();
    });
  }

  void _accept(Map<Object?, Object?>? data) {
    if (data != null) access = AppleAccess.fromMap(data);
  }

  Future<void> _products() async {
    final items = await _channel.invokeListMethod<Object?>('products') ?? [];
    price = null;
    trialAvailable = false;
    for (final item in items.whereType<Map>()) {
      if (item['id'] == unlockId) price = item['price'] as String?;
      if (item['id'] == trialId) trialAvailable = true;
    }
  }

  Future<void> refresh() => _run(() async {
    _accept(await _channel.invokeMapMethod<Object?, Object?>('refresh'));
    await _products();
  });
  Future<void> restore() => _run(() async {
    _accept(await _channel.invokeMapMethod<Object?, Object?>('restore'));
    if (access?.paid != true && access?.legacy != true) {
      message = 'No permanent unlock was found for this Apple Account.';
    }
    await _products();
  });
  Future<void> purchase({bool trial = false}) => _run(() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'purchase',
      {'id': trial ? trialId : unlockId},
    );
    if (result?['access'] is Map) {
      _accept(Map<Object?, Object?>.from(result!['access'] as Map));
    }
    if (result?['outcome'] == 'pending') {
      message =
          'Your purchase is awaiting approval. Access will update when Apple confirms it.';
    }
  });
  Future<void> redeem() => _run(() async {
    await _channel.invokeMethod<void>('redeem');
  });
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await action();
    } on PlatformException catch (error) {
      message =
          error.message ?? 'The App Store is unavailable. Please try again.';
    } catch (_) {
      message =
          'Access could not be checked. Please try again or restore your purchases.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
