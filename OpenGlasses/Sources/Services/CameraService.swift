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
        print("[CAMERA] ensurePermission() called. permissionGranted=\(permissionGranted)")
        if permissionGranted {
            print("[CAMERA] Permission already granted (cached)")
            return
        }

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

        // Skip checkPermissionStatus -- it fails when no devices have permission yet.
        // Go straight to requestPermission which triggers the Meta AI permission dialog.
        do {
            NSLog("[Camera] Requesting camera permission from Meta SDK...")
            let status = try await Wearables.shared.requestPermission(.camera)
            NSLog("[Camera] requestPermission returned: %@", String(describing: status))

            if status == .granted {
                permissionGranted = true
                NSLog("[Camera] Camera permission granted!")
                return
            } else {
                NSLog("[Camera] Camera permission denied by user")
                throw CameraError.permissionDenied
            }
        } catch let error as CameraError {
            throw error  // Re-throw our own errors
        } catch {
            NSLog("[Camera] Permission request failed: %@ -- error type: %@",
                  error.localizedDescription, String(describing: type(of: error)))

            // If it's a PermissionError, the Meta AI app might not have shown the dialog.
            // Try checkPermissionStatus as fallback -- maybe permission was already granted.
            do {
                let fallbackStatus = try await Wearables.shared.checkPermissionStatus(.camera)
                if fallbackStatus == .granted {
                    permissionGranted = true
                    NSLog("[Camera] Permission was already granted (fallback check)")
                    return
                }
            } catch {
                NSLog("[Camera] Fallback checkPermissionStatus also failed: %@", error.localizedDescription)
            }

            // Surface the real error to the user
            throw CameraError.permissionDenied
        }
    }

    // MARK: - Photo Capture

    /// Capture a photo from the glasses camera.
    /// Returns JPEG data of the captured photo.
    func capturePhoto() async throws -> Data {
        print("[CAMERA] capturePhoto() called")
        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        print("[CAMERA] Ensuring camera permission...")
        try await ensurePermission()
        print("[CAMERA] Permission OK, creating photo session")

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
