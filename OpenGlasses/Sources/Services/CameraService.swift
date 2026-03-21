import Foundation
import AVFoundation
import MWDATCore
import MWDATCamera
import UIKit

/// Service for capturing photos from Ray-Ban Meta smart glasses camera.
///
/// ## Meta DAT SDK Camera Flow (documented from official API reference):
///
/// 1. **Registration**: `Wearables.configure()` → `startRegistration()` → state reaches 3 (.registered)
/// 2. **Permission**: `checkPermissionStatus(.camera)` → if not .granted → `requestPermission(.camera)`
///    - `requestPermission` opens Meta AI app. User grants permission. Callback URL returns to our app.
///    - `handleUrl()` must be called with the callback URL to complete the flow.
///    - After permission granted, devices appear in `devicesStream()`.
/// 3. **Device**: `AutoDeviceSelector` picks from `Wearables.shared.devices`.
///    - Devices ONLY appear after at least one permission is granted.
/// 4. **StreamSession**: `StreamSession(config, deviceSelector)` → `.start()` → waits for `.streaming`
///    - States: `.stopped` → `.waitingForDevice` → `.starting` → `.streaming`
///    - `.waitingForDevice` means no device in selector — permission may need re-granting.
/// 5. **Capture**: `session.capturePhoto(format: .jpeg)` → delivers via `photoDataPublisher`
///    - Returns false if no active device session or capture already in progress.
///    - Video pauses during capture and auto-resumes after photo delivery.
/// 6. **Cleanup**: `session.stop()` — always stop when done.
///
/// ## Key gotcha:
/// `checkPermissionStatus(.camera)` is SYNCHRONOUS (returns PermissionStatus, throws on error).
/// `requestPermission(.camera)` is ASYNC (opens Meta AI app, waits for callback).
/// Always check first, only request if needed.
@MainActor
class CameraService: ObservableObject {
    @Published var lastPhoto: UIImage?
    @Published var isCaptureInProgress: Bool = false
    @Published var isStreaming: Bool = false
    /// Whether camera permission has been confirmed (survives across captures, resets on app launch)
    @Published var isCameraPermissionGranted: Bool = false

    private let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
    private var streamSession: StreamSession?
    private var photoListenerToken: (any AnyListenerToken)?
    private var stateListenerToken: (any AnyListenerToken)?
    private var videoFrameListenerToken: (any AnyListenerToken)?
    private var photoContinuation: CheckedContinuation<Data, Error>?

    /// Callback for continuous video frames
    var onVideoFrame: ((UIImage) -> Void)?
    private(set) var latestFrame: UIImage?

    var onRegistrationProgress: ((Int) -> Void)?

    // MARK: - Permission

    private func waitForRegistration(minState: Int, timeoutSeconds: Double) async -> Int {
        let waitStart = ContinuousClock.now
        while true {
            let state = Wearables.shared.registrationState.rawValue
            onRegistrationProgress?(state)
            if state >= minState { return state }
            if ContinuousClock.now - waitStart > .seconds(timeoutSeconds) { return state }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Ensure camera permission is granted. Uses checkPermissionStatus first (no UI),
    /// only opens Meta AI app via requestPermission if not already granted.
    func ensurePermission() async throws {
        print("[CAMERA] ensurePermission() called. isCameraPermissionGranted=\(isCameraPermissionGranted)")

        // Fast path: already confirmed this session
        if isCameraPermissionGranted {
            print("[CAMERA] Permission already granted (cached)")
            return
        }

        // iOS camera permission (required before Meta SDK camera works)
        let iosVideoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if iosVideoStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.permissionDenied }
        } else if iosVideoStatus == .denied || iosVideoStatus == .restricted {
            throw CameraError.permissionDenied
        }

        // Wait for SDK registration state 3
        let settledState = await waitForRegistration(minState: 3, timeoutSeconds: 15)
        if settledState < 3 {
            NSLog("[Camera] State %d — not fully registered", settledState)
            throw CameraError.sdkNotRegistered
        }

        // CHECK permission first (synchronous, no UI) — avoids opening Meta AI app if already granted
        do {
            let currentStatus = try await Wearables.shared.checkPermissionStatus(.camera)
            NSLog("[Camera] checkPermissionStatus returned: %@", String(describing: currentStatus))
            if currentStatus == .granted {
                isCameraPermissionGranted = true
                NSLog("[Camera] Permission already granted (checkPermissionStatus)")
                return
            }
        } catch {
            NSLog("[Camera] checkPermissionStatus threw: %@ — will request", error.localizedDescription)
            // Fall through to requestPermission
        }

        // REQUEST permission (opens Meta AI app, waits for callback)
        NSLog("[Camera] Requesting camera permission from Meta AI app...")
        ErrorReporter.shared.report("Requesting camera permission (opening Meta AI)...", source: "camera", level: "info")
        do {
            let status = try await Wearables.shared.requestPermission(.camera)
            NSLog("[Camera] requestPermission returned: %@", String(describing: status))
            if status == .granted {
                isCameraPermissionGranted = true
                return
            } else {
                throw CameraError.permissionDenied
            }
        } catch let error as CameraError {
            throw error
        } catch {
            NSLog("[Camera] requestPermission failed: %@", error.localizedDescription)
            // One more check — maybe permission was granted but the callback errored
            do {
                let fallback = try await Wearables.shared.checkPermissionStatus(.camera)
                if fallback == .granted {
                    isCameraPermissionGranted = true
                    NSLog("[Camera] Permission granted (post-error fallback check)")
                    return
                }
            } catch { }
            throw CameraError.permissionDenied
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() async throws -> Data {
        print("[CAMERA] capturePhoto() called")
        ErrorReporter.shared.report("capturePhoto() called", source: "camera", level: "info")
        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        try await ensurePermission()

        // Check device availability
        let devices = Wearables.shared.devices
        let activeDevice = deviceSelector.activeDevice
        ErrorReporter.shared.report("Devices: \(devices.count), activeDevice=\(String(describing: activeDevice))", source: "camera", level: "info")

        if activeDevice == nil && devices.isEmpty {
            ErrorReporter.shared.report("No devices available — permission may not have completed. Waiting up to 10s...", source: "camera", level: "warning")
            let waitStart = ContinuousClock.now
            while Wearables.shared.devices.isEmpty {
                if ContinuousClock.now - waitStart > .seconds(10) {
                    ErrorReporter.shared.report("No devices appeared after 10s wait", source: "camera", level: "error")
                    throw CameraError.captureFailed
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            ErrorReporter.shared.report("Device appeared: \(Wearables.shared.devices)", source: "camera", level: "info")
        }

        // Create a photo session
        let photoSession = StreamSession(
            streamSessionConfig: StreamSessionConfig(
                videoCodec: .raw,
                resolution: .high,
                frameRate: 15
            ),
            deviceSelector: deviceSelector
        )

        // Listen for photo data
        photoListenerToken = photoSession.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                self?.handlePhotoData(photoData)
            }
        }

        // Listen for errors
        var sessionError: StreamSessionError?
        let errorToken = photoSession.errorPublisher.listen { error in
            NSLog("[Camera] Session error: %@", String(describing: error))
            ErrorReporter.shared.report("StreamSession error: \(error)", source: "camera", level: "error")
            sessionError = error
        }

        // Log state transitions
        let stateToken = photoSession.statePublisher.listen { state in
            NSLog("[Camera] Session state → %@", String(describing: state))
            ErrorReporter.shared.report("Session state → \(state)", source: "camera", level: "debug")
        }

        // Start the stream
        ErrorReporter.shared.report("Starting photo stream session...", source: "camera", level: "info")
        await photoSession.start()

        // Wait for .streaming state (up to 15s)
        let waitStart = ContinuousClock.now
        while photoSession.state != .streaming {
            if ContinuousClock.now - waitStart > .seconds(15) {
                let state = photoSession.state
                ErrorReporter.shared.report("Session stuck at \(state) after 15s (error: \(String(describing: sessionError)))", source: "camera", level: "error")
                await photoSession.stop()
                photoListenerToken = nil
                throw CameraError.captureFailed
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        ErrorReporter.shared.report("Session streaming after \(ContinuousClock.now - waitStart)", source: "camera", level: "info")

        // Brief stabilization
        try await Task.sleep(nanoseconds: 300_000_000)

        // Capture photo
        ErrorReporter.shared.report("Calling capturePhoto(format: .jpeg)...", source: "camera", level: "info")
        let photoData: Data = try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let success = photoSession.capturePhoto(format: .jpeg)
            if !success {
                ErrorReporter.shared.report("capturePhoto returned false — retrying in 0.5s", source: "camera", level: "warning")
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let retrySuccess = photoSession.capturePhoto(format: .jpeg)
                    if !retrySuccess {
                        self.photoContinuation = nil
                        ErrorReporter.shared.report("capturePhoto retry also false (state=\(photoSession.state))", source: "camera", level: "error")
                        continuation.resume(throwing: CameraError.captureFailed)
                    }
                }
            }

            // Timeout
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if let cont = self.photoContinuation {
                    self.photoContinuation = nil
                    ErrorReporter.shared.report("Photo capture timed out after 8s", source: "camera", level: "error")
                    cont.resume(throwing: CameraError.timeout)
                }
            }
        }

        await photoSession.stop()
        photoListenerToken = nil
        _ = errorToken
        _ = stateToken

        if let image = UIImage(data: photoData) {
            lastPhoto = image
        }

        ErrorReporter.shared.report("Photo captured: \(photoData.count) bytes", source: "camera", level: "info")
        return photoData
    }

    private func handlePhotoData(_ photoData: PhotoData) {
        guard let continuation = photoContinuation else { return }
        photoContinuation = nil
        continuation.resume(returning: photoData.data)
    }

    // MARK: - Continuous Video Streaming

    func startStreaming() async throws {
        guard !isStreaming else { return }
        try await ensurePermission()

        if streamSession == nil {
            let session = StreamSession(
                streamSessionConfig: StreamSessionConfig(
                    videoCodec: .raw,
                    resolution: .low,
                    frameRate: 24
                ),
                deviceSelector: deviceSelector
            )
            streamSession = session
            attachVideoListeners(to: session)
        }

        await streamSession!.start()
        isStreaming = true
    }

    private func attachVideoListeners(to session: StreamSession) {
        var frameCount = 0
        videoFrameListenerToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor in
                guard let self else { return }
                frameCount += 1
                if let image = frame.makeUIImage() {
                    self.latestFrame = image
                    self.onVideoFrame?(image)
                }
            }
        }
    }

    func stopStreaming() async {
        guard isStreaming else { return }
        if let session = streamSession { await session.stop() }
        isStreaming = false
        latestFrame = nil
    }

    func tearDown() async {
        await stopStreaming()
        videoFrameListenerToken = nil
        streamSession = nil
        isCameraPermissionGranted = false
    }

    func saveToPhotoLibrary(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}

enum CameraError: LocalizedError {
    case permissionDenied
    case captureFailed
    case timeout
    case notConnected
    case sdkNotRegistered
    case streamNotReady

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .captureFailed: return "Failed to capture photo"
        case .timeout: return "Photo capture timed out"
        case .notConnected: return "Glasses not connected"
        case .sdkNotRegistered: return "Meta SDK not registered — open Meta app first"
        case .streamNotReady: return "Camera stream not ready — try again"
        }
    }
}
