import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../partners/data/ministry_enrollment_service.dart';

const androidPurchasesEnabled = bool.fromEnvironment(
  'STUDYBIBLE_ANDROID_BILLING',
);

/// Store ownership is supplied by the native Play Billing connection. Trial
/// timestamps live in installation-local native preferences, not study backups.
class AndroidAccess {
  const AndroidAccess({
    required this.paid,
    required this.legacy,
    required this.checkedAt,
    this.trialEndsAt,
  });
  final bool paid, legacy;
  final DateTime checkedAt;
  final DateTime? trialEndsAt;
  bool allows(DateTime now) =>
      paid ||
      legacy ||
      (trialEndsAt != null &&
          (now.isAfter(checkedAt) ? now : checkedAt).isBefore(trialEndsAt!));
  factory AndroidAccess.fromMap(Map<Object?, Object?> data) => AndroidAccess(
    paid: data['paid'] == true,
    legacy: data['legacy'] == true,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(
      (data['checkedAt'] as num).toInt(),
      isUtc: true,
    ),
    trialEndsAt: data['trialEndsAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (data['trialEndsAt'] as num).toInt(),
            isUtc: true,
          )
        : null,
  );
}

class AndroidPurchaseService extends ChangeNotifier {
  AndroidPurchaseService({MethodChannel? channel, this.ministryId})
    : _channel = channel ?? const MethodChannel('studybible/play_purchases') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'accessChanged') {
        _accept(Map<Object?, Object?>.from(call.arguments as Map));
        notifyListeners();
      }
    });
  }
  static final instance = AndroidPurchaseService(
    ministryId: () {
      final enrollment = MinistryEnrollmentService.instance.state.value;
      return enrollment?.setupCompleted == true ? enrollment?.ministryId : null;
    },
  );
  final String? Function()? ministryId;
  final MethodChannel _channel;
  AndroidAccess? access;
  String? price;
  String? message;
  bool busy = false;
  bool trialAvailable = false;
  void _accept(Map<Object?, Object?>? data) {
    if (data == null) return;
    access = AndroidAccess.fromMap(data);
    price = data['price'] as String?;
    trialAvailable = data['trialAvailable'] == true;
    message = data['accessWarning'] as String?;
  }

  Future<void> _run(String method, [Map<String, Object?>? arguments]) async {
    if (busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>(method, {
        ...?arguments,
        'ministryId': ministryId?.call(),
      });
      _accept(data);
      if (data?['outcome'] == 'pending') {
        message =
            'Your payment is awaiting approval. Access unlocks after Google Play confirms it.';
      } else if (method == 'restore' &&
          message == null &&
          access?.paid != true &&
          access?.legacy != true) {
        message = 'No permanent unlock was found for this Google Account.';
      }
    } on PlatformException catch (error) {
      message =
          error.message ?? 'Google Play is unavailable. Please try again.';
    } catch (_) {
      message = 'Access could not be checked. Please try again.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> initialize() => _run('initialize');
  Future<void> refresh() => _run('refresh');
  Future<void> restore() => _run('restore');
  Future<void> startTrial() => _run('startTrial');
  Future<void> purchase() => _run('purchase');
}
