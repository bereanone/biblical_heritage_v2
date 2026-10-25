import Flutter
import StoreKit
import StoreKitTest
import UIKit
import XCTest
import WatchConnectivity
@testable import Runner

// These transactions exist only in a disposable Simulator's StoreKit session.
// No Apple Account, live payment, or physical-device data is involved.
@MainActor
final class RunnerTests: XCTestCase {
  func testFreshTrialPurchaseRestorationAndRevocation() async throws {
    let configuration: [String: Any] = [
      "identifier": UUID().uuidString,
      "nonRenewingSubscriptions": [],
      "products": [
        product("studybible_full_access", price: "19.99", family: true),
        product("studybible_trial_14_days", price: "0.00", family: false),
      ],
      "settings": ["_applicationInternalID": "6760154157", "_developerTeamID": "RTCYBY39S5",
                   "_locale": "en_US", "_storefront": "USA", "_storeKitErrors": []],
      "subscriptionGroups": [], "version": ["major": 3, "minor": 0],
    ]
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("payments.storekit")
    try JSONSerialization.data(withJSONObject: configuration).write(to: file)
    let session = try SKTestSession(contentsOf: file)
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions() }
    let messenger = PurchaseTestMessenger()
    let bridge = StudyBiblePurchaseBridge(messenger: messenger)
    _ = bridge // Retain the real bridge while exercising its Flutter channel.
    let fresh = try await messenger.call("initialize", arguments: ["existingCustomer": false])
    XCTAssertEqual(fresh["allowed"] as? Bool, false)
    XCTAssertEqual(fresh["legacy"] as? Bool, false)

    let trial = try await messenger.call("purchase", arguments: ["id": "studybible_trial_14_days"])
    XCTAssertEqual(trial["outcome"] as? String, "purchased")
    let trialAccess = try XCTUnwrap(trial["access"] as? [String: Any])
    XCTAssertEqual(trialAccess["trialStarted"] as? Bool, true)
    XCTAssertEqual(trialAccess["allowed"] as? Bool, true)
    XCTAssertEqual(trialAccess["paid"] as? Bool, false)
    let end = try XCTUnwrap(trialAccess["trialEndsAt"] as? Double)
    let now = try XCTUnwrap(trialAccess["checkedAt"] as? Double)
    XCTAssertEqual((end - now) / 1000, 14 * 24 * 60 * 60, accuracy: 10)
    let restoredTrial = try await messenger.call("restore")
    XCTAssertEqual(restoredTrial["trialEndsAt"] as? Double, end)

    let purchased = try await messenger.call("purchase", arguments: ["id": "studybible_full_access"])
    let paid = try XCTUnwrap(purchased["access"] as? [String: Any])
    XCTAssertEqual(paid["paid"] as? Bool, true)
    let restored = try await messenger.call("restore")
    XCTAssertEqual(restored["paid"] as? Bool, true)

    let transaction = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == "studybible_full_access" })
    try session.refundTransaction(identifier: transaction.identifier)
    let revoked = try await messenger.call("refresh")
    XCTAssertEqual(revoked["paid"] as? Bool, false)
    // The unexpired free trial remains available after refunding the unlock.
    XCTAssertEqual(revoked["allowed"] as? Bool, true)
  }

  func testWatchColdStartDeniesPlaybackUntilVerified() async throws {
    let messenger = PurchaseTestMessenger()
    let watch = WatchRemoteBridge(requiresPurchaseAccess: true)
    watch.attach(messenger: messenger)
    let initial = try await messenger.call("readerAttached")
    XCTAssertEqual(initial["accessAllowed"] as? Bool, false)
    let reply: [String: Any] = await withCheckedContinuation { continuation in
      watch.session(WCSession.default, didReceiveMessage: ["command": "start"]) {
        continuation.resume(returning: $0)
      }
    }
    XCTAssertNotNil(reply["error"])
    XCTAssertFalse(watch.hasNativePlayback)

    watch.setPurchaseAccess(true)
    let granted = try await messenger.call("readerAttached")
    XCTAssertEqual(granted["accessAllowed"] as? Bool, true)
    watch.setPurchaseAccess(false)
    // A reader-state publication cannot reopen access after revocation.
    _ = try? await messenger.call("publishState", arguments: [
      "book": 1, "chapter": 1, "verse": 1, "loop": "off",
      "playing": false, "accessAllowed": true,
    ])
    let revoked = try await messenger.call("readerAttached")
    XCTAssertEqual(revoked["accessAllowed"] as? Bool, false)
    XCTAssertEqual(revoked["playing"] as? Bool, false)
  }

  func testExplicitBillingOffWatchBuildRetainsAccess() async throws {
    let messenger = PurchaseTestMessenger()
    let watch = WatchRemoteBridge(requiresPurchaseAccess: false)
    watch.attach(messenger: messenger)
    let state = try await messenger.call("readerAttached")
    XCTAssertEqual(state["accessAllowed"] as? Bool, true)
  }

  private func product(_ id: String, price: String, family: Bool) -> [String: Any] {
    ["displayPrice": price, "familyShareable": family, "internalID": UUID().uuidString,
     "localizations": [["description": "StudyBible payment verification", "displayName": id, "locale": "en_US"]],
     "productID": id, "referenceName": id, "type": "NonConsumable"]
  }
}

private final class PurchaseTestMessenger: NSObject, FlutterBinaryMessenger {
  private var handler: FlutterBinaryMessageHandler?
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    self.handler = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler = nil }
  @MainActor
  func call(_ method: String, arguments: [String: Any]? = nil) async throws -> [String: Any] {
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let data = codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))
    return try await withCheckedThrowingContinuation { continuation in
      guard let handler else { continuation.resume(throwing: HarnessError.missingHandler); return }
      handler(data) { reply in
        guard let reply, let value = codec.decodeEnvelope(reply) as? [String: Any] else {
          continuation.resume(throwing: HarnessError.invalidResponse); return
        }
        continuation.resume(returning: value)
      }
    }
  }
  enum HarnessError: Error { case missingHandler, invalidResponse }
}
