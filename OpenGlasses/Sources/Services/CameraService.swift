import Foundation
import AVFoundation
import MWDATCore
import MWDATCamera
import UIKit

/// Service for capturing photos from Ray-Ban Meta smart glasses camera.
///
/// Matches VisionClaw's pattern: the `StreamSession` is created once and reused across
/// start/stop cycles. Permission is checked/requested once, not on every session start.
@MainActor
class CameraService: ObservableObject {
    @Published var lastPhoto: UIImage?
    @Published var isCaptureInProgress: Bool = false
    @Published var isStreaming: Bool = false

    private let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
    private var streamSession: StreamSession?
    private var photoListenerToken: (any AnyListenerToken)?
    private var stateListenerToken: (any AnyListenerToken)?
    private var videoFrameListenerToken: (any AnyListenerToken)?
    private var photoContinuation: CheckedContinuation<Data, Error>?

    /// Whether camera permission has been granted (cached to avoid re-checking).
    private var permissionGranted = false

    /// Callback for continuous video frames (used by Gemini Live mode)
    var onVideoFrame: ((UIImage) -> Void)?

    /// The most recent video frame captured from the glasses camera
    private(set) var latestFrame: UIImage?

    // MARK: - Permission

    /// Ensure camera permission is granted. Waits for SDK registration to complete first,
    /// since checkPermissionStatus throws when registration state < 2.
    /// Only shows the Meta dialog if not already approved.
    /// Optional callback to report SDK registration progress (state 0–3) back to UI.
    var onRegistrationProgress: ((Int) -> Void)?

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

    func ensurePermission() async throws {
        if permissionGranted { return }

        // Camera permission requires SDK registration state 3 (.registered).
        // State 2 gives PermissionError error 0. After backgrounding the SDK
        // typically only auto-recovers to state 2 — we may need to nudge it.
        let regState = Wearables.shared.registrationState
        NSLog("[Camera] SDK state: %d (need 3 for camera permissions)", regState.rawValue)
        onRegistrationProgress?(regState.rawValue)

        // --- iOS Camera Permission ---
        // Meta Wearables SDK requires active iOS camera permissions first before it can register cleanly.
        let iosVideoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if iosVideoStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw CameraError.permissionDenied
            }
        } else if iosVideoStatus == .denied || iosVideoStatus == .restricted {
            throw CameraError.permissionDenied
        }

        // The camera permission APIs are only reliable once fully registered (state 3).
        // State 2 often yields PermissionError from checkPermissionStatus(.camera).
        // Do NOT call startRegistration() here — that belongs in the UI layer only.
        let settledState = await waitForRegistration(minState: 3, timeoutSeconds: 15)
        if settledState < 3 {
            NSLog("[Camera] State %d is not fully registered. Cannot check camera permissions.", settledState)
            throw CameraError.sdkNotRegistered
        }
        NSLog("[Camera] Registration settled at state: %d", settledState)

        NSLog("[Camera] Checking permissions directly with the Meta SDK...")
        
        let maxAttempts = 3
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                NSLog("[Camera] Permission retry %d/%d...", attempt + 1, maxAttempts)
                try? await Task.sleep(nanoseconds: 4_000_000_000) // 4s retry wait to give Bluetooth time to spin up
            }

            do {
                // Wait for SDK to be ready before calling checkPermissionStatus.
                // Camera permission checks need full registration state 3.
                let readyState = await waitForRegistration(minState: 3, timeoutSeconds: 10)
                if readyState < 3 {
                    throw CameraError.sdkNotRegistered
                }

                // Rely on the SDK's internal connection state.
                let status = try await Wearables.shared.checkPermissionStatus(.camera)
                NSLog("[Camera] checkPermissionStatus returned: %@", String(describing: status))
                if status == .granted {
                    NSLog("[Camera] Permission already granted")
                    permissionGranted = true
                    return
                }

                NSLog("[Camera] Permission not yet granted, requesting...")

                let requestStatus = try await Wearables.shared.requestPermission(.camera)
                NSLog("[Camera] requestPermission returned: %@", String(describing: requestStatus))
                
                guard requestStatus == .granted else {
                    throw CameraError.permissionDenied
                }
                
                permissionGranted = true
                NSLog("[Camera] Permission granted via request")
                return
            } catch {
                NSLog("[Camera] Permission attempt %d/%d failed: %@",
                      attempt + 1, maxAttempts, error.localizedDescription)
                
                // Log registration state for diagnosis — but never call startRegistration() from here.
                if let nsError = error as NSError?, nsError.domain == "MWDATCore.PermissionError" {
                    let currentState = Wearables.shared.registrationState.rawValue
                    NSLog("[Camera] PermissionError at registration state %d — user must complete registration first", currentState)
                    if currentState < 3 {
                        throw CameraError.sdkNotRegistered
                    }
                }
                
                if (error as? CameraError) == .permissionDenied {
                    throw CameraError.permissionDenied
                }

                if attempt == maxAttempts - 1 {
                    throw CameraError.sdkNotRegistered
                }
            }
        }
    }

    // MARK: - Photo Capture

    /// Capture a photo from the glasses camera.
    /// Returns JPEG data of the captured photo.
    func capturePhoto() async throws -> Data {
        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        try await ensurePermission()

        // Create a temporary stream session for photo capture (needs .high resolution)
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

        // Start the stream (required before capture)
        await photoSession.start()

        // Wait briefly for streaming to stabilize
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s

        // Capture the photo
        let photoData: Data = try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let success = photoSession.capturePhoto(format: .jpeg)
            if !success {
                self.photoContinuation = nil
                continuation.resume(throwing: CameraError.captureFailed)
            }

            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let cont = self.photoContinuation {
                    self.photoContinuation = nil
                    cont.resume(throwing: CameraError.timeout)
                }
            }
        }

        // Stop the photo session
        await photoSession.stop()
        photoListenerToken = nil

        // Store the image for display
        if let image = UIImage(data: photoData) {
            lastPhoto = image
        }

        print("📸 Photo captured: \(photoData.count) bytes")
        return photoData
    }

    private func handlePhotoData(_ photoData: PhotoData) {
        guard let continuation = photoContinuation else { return }
        photoContinuation = nil
        continuation.resume(returning: photoData.data)
    }

    // MARK: - Continuous Video Streaming (for Gemini Live)

    /// Start continuous video streaming from the glasses camera.
    /// Frames are delivered via `onVideoFrame` callback and stored in `latestFrame`.
    ///
    /// Following VisionClaw's pattern: the StreamSession is created once and reused.
    /// Permission is handled separately via `ensurePermission()`.
    func startStreaming() async throws {
        guard !isStreaming else { return }

        try await ensurePermission()

        // Create the stream session if we don't have one yet (first start or after resolution change).
        // VisionClaw creates the session once in init and reuses it across start/stop cycles.
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
            NSLog("[Camera] Created new StreamSession (.low, 24fps)")
        }

        await streamSession!.start()
        isStreaming = true
        NSLog("[Camera] Streaming started")
    }

    /// Attach video frame listeners to a StreamSession.
    private func attachVideoListeners(to session: StreamSession) {
        var frameCount = 0
        videoFrameListenerToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor in
                guard let self else { return }
                frameCount += 1
                if let image = frame.makeUIImage() {
                    self.latestFrame = image
                    if frameCount <= 3 || frameCount % 30 == 0 {
                        NSLog("[Camera] Video frame #%d received (%dx%d)",
                              frameCount, Int(image.size.width), Int(image.size.height))
                    }
                    self.onVideoFrame?(image)
                } else {
                    if frameCount <= 3 {
                        NSLog("[Camera] Frame #%d: makeUIImage() returned nil", frameCount)
                    }
                }
            }
        }
    }

    /// Stop continuous video streaming.
    /// The StreamSession is stopped but kept alive for reuse (matching VisionClaw's pattern).
    func stopStreaming() async {
        guard isStreaming else { return }
        if let session = streamSession {
            await session.stop()
        }
        isStreaming = false
        latestFrame = nil
        NSLog("[Camera] Streaming stopped (session kept alive for reuse)")
    }

    /// Tear down everything — called on mode switch or app termination.
    func tearDown() async {
        await stopStreaming()
        videoFrameListenerToken = nil
        streamSession = nil
        permissionGranted = false
        NSLog("[Camera] Torn down completely")
    }

    /// Save photo to the camera roll
    func saveToPhotoLibrary(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        print("📸 Photo saved to camera roll")
    }
}

enum CameraError: LocalizedError {
    case permissionDenied
    case captureFailed
    case timeout
    case notConnected
    case sdkNotRegistered

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .captureFailed: return "Failed to capture photo"
        case .timeout: return "Photo capture timed out"
        case .notConnected: return "Glasses not connected"
        case .sdkNotRegistered: return "Meta SDK not registered — open Meta app first"
        }
    }
}
