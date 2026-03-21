import Foundation
import AVFoundation
import MWDATCore
import MWDATCamera
import UIKit

/// Camera service modeled after Meta's official CameraAccess sample app.
///
/// Key pattern (from sample's StreamSessionViewModel):
///   - ONE persistent StreamSession created at init, reused across captures
///   - Monitor activeDeviceStream() for device availability
///   - Start streaming FIRST, then capture from the running stream
///   - Never create/destroy sessions per capture
///
/// Flow:
///   1. App launch → CameraService.init() creates StreamSession + listeners
///   2. User grants camera permission → call startStreaming()
///   3. Session goes: stopped → waitingForDevice → starting → streaming
///   4. When streaming, capturePhoto() works instantly
///   5. Session stays alive until explicitly stopped
@MainActor
class CameraService: ObservableObject {
    @Published var lastPhoto: UIImage?
    @Published var isCaptureInProgress: Bool = false
    @Published var isStreaming: Bool = false
    @Published var isCameraPermissionGranted: Bool = false
    @Published var hasActiveDevice: Bool = false
    @Published var streamingStatus: StreamingStatus = .stopped
    @Published var lastError: String?

    enum StreamingStatus: String {
        case streaming, waiting, stopped
    }

    // Core SDK objects — created ONCE, reused
    private let wearables: WearablesInterface
    private let deviceSelector: AutoDeviceSelector
    private let streamSession: StreamSession

    // Listener tokens
    private var stateListenerToken: (any AnyListenerToken)?
    private var videoFrameListenerToken: (any AnyListenerToken)?
    private var errorListenerToken: (any AnyListenerToken)?
    private var photoDataListenerToken: (any AnyListenerToken)?
    private var deviceMonitorTask: Task<Void, Never>?

    // Photo capture continuation
    private var photoContinuation: CheckedContinuation<Data, Error>?

    /// Callback for video frames (used by vision features)
    var onVideoFrame: ((UIImage) -> Void)?
    private(set) var latestFrame: UIImage?

    // MARK: - Init (matches sample app pattern)

    init() {
        let w = Wearables.shared
        self.wearables = w
        self.deviceSelector = AutoDeviceSelector(wearables: w)

        // Create ONE StreamSession with photo-quality config — kept alive for app lifetime
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .high,
            frameRate: 15
        )
        self.streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

        // Monitor device availability via async stream (from sample app line 65-69)
        deviceMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await device in self.deviceSelector.activeDeviceStream() {
                self.hasActiveDevice = device != nil
                if device != nil {
                    ErrorReporter.shared.report("Device became available: \(String(describing: device))", source: "camera", level: "info")
                }
            }
        }

        // Subscribe to session state changes (from sample app line 73-77)
        stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusFromState(state)
                ErrorReporter.shared.report("StreamSession state → \(state)", source: "camera", level: "debug")
            }
        }

        // Subscribe to video frames (from sample app line 81-92)
        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let image = videoFrame.makeUIImage() {
                    self.latestFrame = image
                    self.onVideoFrame?(image)
                }
            }
        }

        // Subscribe to errors (from sample app line 96-104)
        errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let msg = self.formatStreamingError(error)
                self.lastError = msg
                ErrorReporter.shared.report("StreamSession error: \(msg)", source: "camera", level: "error")
            }
        }

        // Subscribe to photo capture events (from sample app line 110-118)
        photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let image = UIImage(data: photoData.data) {
                    self.lastPhoto = image
                }
                // Resume the capture continuation if waiting
                if let cont = self.photoContinuation {
                    self.photoContinuation = nil
                    cont.resume(returning: photoData.data)
                }
            }
        }

        updateStatusFromState(streamSession.state)
    }

    // MARK: - Permission (matches sample app handleStartStreaming pattern)

    /// Check and request camera permission, then start streaming.
    /// This is the single entry point — call from the camera pill or before first capture.
    func ensurePermissionAndStartStreaming() async throws {
        // iOS camera permission first
        let iosStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if iosStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.permissionDenied }
        } else if iosStatus == .denied || iosStatus == .restricted {
            throw CameraError.permissionDenied
        }

        // Meta SDK permission (matches sample app lines 121-137)
        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            if status == .granted {
                isCameraPermissionGranted = true
                await startStreaming()
                return
            }
        } catch {
            // checkPermissionStatus failed — fall through to request
            ErrorReporter.shared.report("checkPermissionStatus failed: \(error) — will request", source: "camera", level: "warning")
        }

        // Request permission (opens Meta AI app)
        ErrorReporter.shared.report("Requesting camera permission...", source: "camera", level: "info")
        do {
            let requestStatus = try await wearables.requestPermission(.camera)
            if requestStatus == .granted {
                isCameraPermissionGranted = true
                await startStreaming()
                return
            }
            throw CameraError.permissionDenied
        } catch let e as CameraError {
            throw e
        } catch {
            ErrorReporter.shared.report("requestPermission failed: \(error)", source: "camera", level: "error")
            throw CameraError.permissionDenied
        }
    }

    // Keep the old name for backward compatibility
    func ensurePermission() async throws {
        try await ensurePermissionAndStartStreaming()
    }

    // MARK: - Streaming (persistent session)

    /// Start the persistent stream session. Call after permission is granted.
    /// The session handles waitingForDevice internally — it auto-connects when a device appears.
    func startStreaming() async {
        guard streamingStatus == .stopped else {
            ErrorReporter.shared.report("startStreaming called but status=\(streamingStatus.rawValue)", source: "camera", level: "debug")
            return
        }
        ErrorReporter.shared.report("Starting persistent stream session...", source: "camera", level: "info")
        await streamSession.start()
        // Don't set isStreaming here — the statePublisher listener handles it
    }

    func stopStreaming() async {
        await streamSession.stop()
        latestFrame = nil
    }

    // MARK: - Photo Capture (from running stream)

    /// Capture a photo from the ALREADY-RUNNING stream.
    /// If stream isn't running yet, starts it and waits for streaming state.
    func capturePhoto() async throws -> Data {
        ErrorReporter.shared.report("capturePhoto() called. streamingStatus=\(streamingStatus.rawValue) hasActiveDevice=\(hasActiveDevice)", source: "camera", level: "info")
        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        // Ensure permission + streaming
        if !isCameraPermissionGranted {
            try await ensurePermissionAndStartStreaming()
        } else if streamingStatus == .stopped {
            await startStreaming()
        }

        // Wait for streaming state (the session may be in waitingForDevice/starting)
        if streamingStatus != .streaming {
            ErrorReporter.shared.report("Waiting for streaming state (currently \(streamingStatus.rawValue))...", source: "camera", level: "info")
            let waitStart = ContinuousClock.now
            while streamingStatus != .streaming {
                if ContinuousClock.now - waitStart > .seconds(20) {
                    ErrorReporter.shared.report("Timed out waiting for streaming (stuck at \(streamingStatus.rawValue))", source: "camera", level: "error")
                    throw CameraError.streamNotReady
                }
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        ErrorReporter.shared.report("Stream is live — capturing photo...", source: "camera", level: "info")

        // Capture from the running stream (from sample app line 158-159)
        let photoData: Data = try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let success = streamSession.capturePhoto(format: .jpeg)
            if !success {
                self.photoContinuation = nil
                ErrorReporter.shared.report("capturePhoto(format:) returned false", source: "camera", level: "error")
                continuation.resume(throwing: CameraError.captureFailed)
                return
            }

            // Timeout safety
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let cont = self.photoContinuation {
                    self.photoContinuation = nil
                    ErrorReporter.shared.report("Photo capture timed out after 10s", source: "camera", level: "error")
                    cont.resume(throwing: CameraError.timeout)
                }
            }
        }

        ErrorReporter.shared.report("Photo captured: \(photoData.count) bytes", source: "camera", level: "info")
        return photoData
    }

    func saveToPhotoLibrary(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    // MARK: - State Management

    private func updateStatusFromState(_ state: StreamSessionState) {
        switch state {
        case .stopped:
            streamingStatus = .stopped
            isStreaming = false
        case .waitingForDevice, .starting, .stopping, .paused:
            streamingStatus = .waiting
            isStreaming = false
        case .streaming:
            streamingStatus = .streaming
            isStreaming = true
        @unknown default:
            break
        }
    }

    private func formatStreamingError(_ error: StreamSessionError) -> String {
        switch error {
        case .internalError: return "Internal camera error"
        case .deviceNotFound: return "Glasses not found"
        case .deviceNotConnected: return "Glasses not connected"
        case .timeout: return "Camera timed out"
        case .permissionDenied: return "Camera permission denied"
        case .hingesClosed: return "Open the glasses hinges"
        case .thermalCritical: return "Glasses overheating"
        @unknown default: return "Unknown camera error"
        }
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
        case .sdkNotRegistered: return "Meta SDK not registered"
        case .streamNotReady: return "Camera not ready — try again"
        }
    }
}
