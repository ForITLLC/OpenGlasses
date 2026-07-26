import XCTest
@testable import OpenGlasses

/// The Meta DAT SDK answers an unconfigured `Wearables.shared` with `fatalError`,
/// not a throw. `WearablesRuntime.isConfigured` is therefore the only thing standing
/// between a failed `configure()` at launch and a hard crash — and because the trap
/// lives inside the SDK, nothing in our own code reads as dangerous at the call site.
///
/// Builds 18 and 19 shipped before these guards existed. The crash was only caught
/// once a test target existed to run the host app: CI run 30207539103 died in
/// `MWDATCore/Wearables.swift:191`, and b6a2c29 added the guards.
///
/// These tests pin the fail-soft contract so that re-introducing a bare
/// `Wearables.shared` touch fails here, in CI, instead of on a user's device.
/// They assert behaviour reachable on a simulator — no glasses, no registration.
@MainActor
final class WearablesRuntimeGuardTests: XCTestCase {

    /// Runs `body` with the SDK pinned to "unconfigured", then restores the previous
    /// value. Pinning explicitly matters: the host app calls `configure()` at launch,
    /// so relying on ambient state would make these tests pass or fail by accident.
    private func withUnconfiguredSDK(_ body: () async throws -> Void) async rethrows {
        let saved = WearablesRuntime.isConfigured
        WearablesRuntime.isConfigured = false
        defer { WearablesRuntime.isConfigured = saved }
        try await body()
    }

    // MARK: - CameraService

    func testCameraServiceIsInertWhenSDKUnconfigured() async {
        await withUnconfiguredSDK {
            let camera = CameraService()
            XCTAssertEqual(camera.lastError, "Meta SDK not registered — camera unavailable")
            XCTAssertFalse(camera.isStreaming)
            XCTAssertFalse(camera.hasActiveDevice)
        }
    }

    func testStartStreamingThrowsInsteadOfTrappingWhenSDKUnconfigured() async {
        await withUnconfiguredSDK {
            let camera = CameraService()
            do {
                try await camera.ensurePermissionAndStartStreaming()
                XCTFail("expected .sdkNotRegistered, but the call returned normally")
            } catch let error as CameraError {
                guard case .sdkNotRegistered = error else {
                    return XCTFail("expected .sdkNotRegistered, got \(error)")
                }
            } catch {
                XCTFail("expected CameraError, got \(type(of: error)): \(error)")
            }
        }
    }

    func testCapturePhotoThrowsInsteadOfTrappingWhenSDKUnconfigured() async {
        await withUnconfiguredSDK {
            let camera = CameraService()
            do {
                _ = try await camera.capturePhoto()
                XCTFail("expected .sdkNotRegistered, but the call returned data")
            } catch let error as CameraError {
                guard case .sdkNotRegistered = error else {
                    return XCTFail("expected .sdkNotRegistered, got \(error)")
                }
            } catch {
                XCTFail("expected CameraError, got \(type(of: error)): \(error)")
            }
        }
    }

    // MARK: - GlassesConnectionService

    func testGlassesConnectionIsInertWhenSDKUnconfigured() async {
        await withUnconfiguredSDK {
            let glasses = GlassesConnectionService()
            XCTAssertEqual(glasses.connectionStatus, "Meta SDK not registered")
            XCTAssertFalse(glasses.isConnected)
        }
    }

    /// `connect()` must fail soft rather than reach `Wearables.shared.registrationState`.
    /// Reaching it would trap, so "status never became Registering..." is the assertion
    /// that proves the guard ran before the SDK was touched.
    func testConnectFailsSoftWhenSDKUnconfigured() async {
        await withUnconfiguredSDK {
            let glasses = GlassesConnectionService()
            await glasses.connect()
            XCTAssertEqual(glasses.connectionStatus, "Meta SDK not registered")
            XCTAssertFalse(glasses.isConnected)
        }
    }

    // MARK: - User-facing copy

    /// What the user sees in place of the crash.
    func testSDKNotRegisteredHasUserFacingMessage() {
        XCTAssertEqual(CameraError.sdkNotRegistered.errorDescription, "Meta SDK not registered")
    }
}
