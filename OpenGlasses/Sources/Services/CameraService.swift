import Combine
import Foundation
import AVFoundation
import MWDATCore
import MWDATCamera
import UIKit
import Photos

/// DAT 1.x keeps the glasses connection (`DeviceSession`) separate from its
/// camera capability (`Camera.stream`). A stopped device session is terminal;
/// later captures create a new one. Stopping preview leaves a live session reusable.
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

    // A live DeviceSession can be reused; each camera/stream is one burst only.
    // Optional because `Wearables.shared` hard-traps when configure() failed; in
    // that case the service is constructed inert and every entry point throws
    // `.sdkNotRegistered` instead of crashing the app.
    private let wearables: WearablesInterface?
    private let deviceSelector: AutoDeviceSelector?
    private var deviceSession: DeviceSession?
    private var stoppingSession: DeviceSession?
    private var camera: Camera?
    private var stoppingCamera: Camera?
    private var cameraID = UUID()
    private var streamSession: MWDATCamera.Stream?
    private var sessionStateToken: (any AnyListenerToken)?
    private var sessionErrorToken: (any AnyListenerToken)?
    private var lifecycleID = UUID()
    private var isStartingSession = false
    private var pendingPermissionRequests = 0

    // Listener tokens
    private var stateListenerToken: (any AnyListenerToken)?
    private var videoFrameListenerToken: (any AnyListenerToken)?
    private var errorListenerToken: (any AnyListenerToken)?
    private var photoDataListenerToken: (any AnyListenerToken)?
    private var deviceMonitorTask: Task<Void, Never>?

    // Photo capture continuation
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var photoRequestID: UUID?

    /// Callback for video frames (used by vision features)
    var onVideoFrame: ((UIImage) -> Void)?
    private(set) var latestFrame: UIImage?

    // MARK: - Init (matches sample app pattern)

    init() {
        guard WearablesRuntime.isConfigured else {
            self.wearables = nil
            self.deviceSelector = nil
            self.streamSession = nil
            self.lastError = "Meta SDK not registered — camera unavailable"
            ErrorReporter.shared.report("CameraService inert: Wearables.configure() never succeeded", source: "camera", level: "error")
            return
        }

        let w = Wearables.shared
        self.wearables = w
        let selector = AutoDeviceSelector(wearables: w)
        self.deviceSelector = selector

        deviceMonitorTask = Task { @MainActor [weak self] in
            for await device in selector.activeDeviceStream() {
                guard let self else { return }
                self.hasActiveDevice = device != nil
            }
        }
    }

    private func attachStreamListeners(_ stream: MWDATCamera.Stream, lifecycle: UUID, burst: UUID) {
        stateListenerToken = stream.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleID == lifecycle, self.cameraID == burst else { return }
                self.updateStatusFromState(state)
            }
        }
        videoFrameListenerToken = stream.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleID == lifecycle, self.cameraID == burst,
                      let image = frame.makeUIImage() else { return }
                self.latestFrame = image
                self.onVideoFrame?(image)
            }
        }
        errorListenerToken = stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleID == lifecycle, self.cameraID == burst else { return }
                self.lastError = error.localizedDescription
                self.finishPhoto(throwing: error)
            }
        }
        photoDataListenerToken = stream.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleID == lifecycle, self.cameraID == burst else { return }
                self.lastPhoto = UIImage(data: photoData.data)
                let continuation = self.photoContinuation
                self.photoContinuation = nil
                self.photoRequestID = nil
                continuation?.resume(returning: photoData.data)
            }
        }
    }

    private func finishPhoto(throwing error: Error) {
        let continuation = photoContinuation
        photoContinuation = nil
        photoRequestID = nil
        continuation?.resume(throwing: error)
    }

    /// Detach a burst immediately, retaining its camera until the SDK confirms
    /// `.stopped`. Queued callbacks from this burst cannot touch the next one.
    private func detachCamera() {
        cameraID = UUID()
        let tokens = [stateListenerToken, videoFrameListenerToken, errorListenerToken,
                      photoDataListenerToken]
        stateListenerToken = nil
        videoFrameListenerToken = nil
        errorListenerToken = nil
        photoDataListenerToken = nil
        if let camera {
            camera.stop()
            stoppingCamera = camera
        }
        camera = nil
        streamSession = nil
        latestFrame = nil
        streamingStatus = .stopped
        isStreaming = false
        Task { for token in tokens { await token?.cancel() } }
    }

    private func releaseSession() {
        lifecycleID = UUID()
        detachCamera()
        let tokens = [sessionStateToken, sessionErrorToken]
        sessionStateToken = nil
        sessionErrorToken = nil
        deviceSession = nil
        isStartingSession = false
        Task { for token in tokens { await token?.cancel() } }
    }

    // MARK: - Permission (matches sample app handleStartStreaming pattern)

    /// Check and request camera permission, then start streaming.
    /// This is the single entry point — call from the camera pill or before first capture.
    func ensurePermissionAndStartStreaming() async throws {
        guard let wearables else { throw CameraError.sdkNotRegistered }
        if deviceSession?.state == .stopped { releaseSession() }
        let permissionLifecycle = lifecycleID
        pendingPermissionRequests += 1
        defer { pendingPermissionRequests -= 1 }

        // iOS camera permission first
        let iosStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if iosStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard lifecycleID == permissionLifecycle, !Task.isCancelled else { throw CancellationError() }
            if !granted { throw CameraError.permissionDenied }
        } else if iosStatus == .denied || iosStatus == .restricted {
            throw CameraError.permissionDenied
        }

        // Meta SDK permission (matches sample app lines 121-137)
        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            guard lifecycleID == permissionLifecycle, !Task.isCancelled else { throw CancellationError() }
            if status == .granted {
                isCameraPermissionGranted = true
                await startStreaming()
                return
            }
        } catch {
            guard lifecycleID == permissionLifecycle, !Task.isCancelled else { throw CancellationError() }
            // checkPermissionStatus failed — fall through to request
            ErrorReporter.shared.report("checkPermissionStatus failed: \(error) — will request", source: "camera", level: "warning")
        }

        // Request permission (opens Meta AI app)
        ErrorReporter.shared.report("Requesting camera permission...", source: "camera", level: "info")
        do {
            let requestStatus = try await wearables.requestPermission(.camera)
            guard lifecycleID == permissionLifecycle, !Task.isCancelled else { throw CancellationError() }
            if requestStatus == .granted {
                isCameraPermissionGranted = true
                await startStreaming()
                return
            }
            throw CameraError.permissionDenied
        } catch let e as CameraError {
            throw e
        } catch {
            guard lifecycleID == permissionLifecycle, !Task.isCancelled else { throw CancellationError() }
            ErrorReporter.shared.report("requestPermission failed: \(error)", source: "camera", level: "error")
            throw CameraError.permissionDenied
        }
    }

    // Keep the old name for backward compatibility
    func ensurePermission() async throws {
        try await ensurePermissionAndStartStreaming()
    }

    // MARK: - Streaming (persistent session)

    /// Start or reuse a device session, then attach and start its camera stream.
    func startStreaming() async {
        guard let wearables, let deviceSelector else { return }
        if deviceSession?.state == .stopped { releaseSession() }
        guard !isStartingSession else { return }
        // Starting a previously stopped stream is unreliable in DAT 1.0.x.
        // Leave an already-live burst alone; otherwise detach it and acquire a
        // fresh Camera below, after the old camera actually reaches `.stopped`.
        if let camera, let streamSession {
            switch streamSession.state {
            case .streaming, .starting, .waitingForDevice, .paused:
                if camera.state == .started || camera.state == .starting { return }
            case .stopped, .stopping:
                break
            @unknown default:
                break
            }
            detachCamera()
        }
        // A pause belongs to the glasses. Do not open a competing session.
        if deviceSession?.state == .paused { return }
        isStartingSession = true
        lastError = nil
        streamingStatus = .waiting
        let lifecycle = lifecycleID
        defer { if lifecycleID == lifecycle { isStartingSession = false } }
        do {
            // A previous stop is asynchronous on the glasses even though stop()
            // itself is synchronous. Do not open a competing session meanwhile.
            if let stopping = stoppingSession {
                let deadline = ContinuousClock.now + .seconds(20)
                while stopping.state != .stopped {
                    guard lifecycleID == lifecycle, ContinuousClock.now < deadline else {
                        throw CameraError.streamNotReady
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard lifecycleID == lifecycle else { return }
                stoppingSession = nil
            }
            if let stopping = stoppingCamera {
                let deadline = ContinuousClock.now + .seconds(20)
                while stopping.state != .stopped {
                    guard lifecycleID == lifecycle, ContinuousClock.now < deadline else {
                        throw CameraError.streamNotReady
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard lifecycleID == lifecycle else { return }
                stoppingCamera = nil
            }
            guard lifecycleID == lifecycle else { return }
            let session: DeviceSession
            if let current = deviceSession {
                session = current
            } else {
                session = try wearables.createSession(deviceSelector: deviceSelector)
                deviceSession = session
                sessionStateToken = session.statePublisher.listen { [weak self] state in
                    Task { @MainActor [weak self] in
                        guard let self, self.lifecycleID == lifecycle else { return }
                        if state == .stopped {
                            self.finishPhoto(throwing: CameraError.streamNotReady)
                            self.releaseSession()
                        }
                    }
                }
                sessionErrorToken = session.errorPublisher.listen { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, self.lifecycleID == lifecycle else { return }
                        self.lastError = error.localizedDescription
                        self.finishPhoto(throwing: error)
                    }
                }
                try session.start()
            }
            let deadline = ContinuousClock.now + .seconds(20)
            while session.state != .started {
                guard lifecycleID == lifecycle, session.state != .stopped,
                      ContinuousClock.now < deadline else { throw CameraError.streamNotReady }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard lifecycleID == lifecycle else { return }
            let config = StreamConfiguration(videoCodec: .raw, audioCodec: nil,
                                             resolution: .high, frameRate: 15)
            guard let camera = try session.addCamera(config: config) else {
                throw CameraError.streamNotReady
            }
            self.camera = camera
            self.streamSession = camera.stream
            let burst = UUID()
            cameraID = burst
            attachStreamListeners(camera.stream, lifecycle: lifecycle, burst: burst)
            camera.stream.start()
        } catch {
            guard lifecycleID == lifecycle else { return }
            lastError = error.localizedDescription
            endDeviceSession(throwing: error)
            ErrorReporter.shared.report("Camera start failed: \(error.localizedDescription)", source: "camera", level: "error")
        }
    }

    private func endDeviceSession(throwing error: Error) {
        finishPhoto(throwing: error)
        if let session = deviceSession {
            session.stop()
            stoppingSession = session
        }
        releaseSession()
    }

    func stopStreaming() async {
        if isStartingSession || pendingPermissionRequests > 0 || photoContinuation != nil {
            // Invalidate a pending permission/start/capture, so it cannot resume after Stop.
            endDeviceSession(throwing: CameraError.streamNotReady)
        } else {
            detachCamera()
        }
        latestFrame = nil
        isStreaming = false
        streamingStatus = .stopped
    }

    /// Synchronous cancellation used by the listening switch, before any new
    /// conversation can start. A queued task must not stop a newer capture.
    func cancelPendingCapture() {
        endDeviceSession(throwing: CancellationError())
        latestFrame = nil
    }

    // MARK: - Photo Capture (from running stream)

    /// Capture a photo from the ALREADY-RUNNING stream.
    /// If stream isn't running yet, starts it and waits for streaming state.
    func capturePhoto() async throws -> Data {
        guard wearables != nil else { throw CameraError.sdkNotRegistered }
        guard !isCaptureInProgress else { throw CameraError.captureFailed }
        if deviceSession?.state == .stopped { releaseSession() }
        let operationLifecycle = lifecycleID
        ErrorReporter.shared.report("capturePhoto() called. streamingStatus=\(streamingStatus.rawValue) hasActiveDevice=\(hasActiveDevice)", source: "camera", level: "info")
        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        // Ensure permission + streaming
        if !isCameraPermissionGranted {
            try await ensurePermissionAndStartStreaming()
        } else if streamingStatus == .stopped {
            await startStreaming()
        }

        guard lifecycleID == operationLifecycle, !Task.isCancelled else { throw CancellationError() }

        guard let streamSession, let captureCamera = camera else { throw CameraError.streamNotReady }
        let captureLifecycle = lifecycleID
        let captureBurst = cameraID
        var captured = false
        defer {
            if lifecycleID == captureLifecycle, cameraID == captureBurst {
                detachCamera()
                if !captured { endDeviceSession(throwing: CameraError.captureFailed) }
            } else if captureCamera.state != .stopped, captureCamera.state != .stopping {
                // A cancelled old operation may only stop its own camera.
                captureCamera.stop()
            }
        }

        // Wait for streaming state (the session may be in waitingForDevice/starting)
        if streamingStatus != .streaming {
            ErrorReporter.shared.report("Waiting for streaming state (currently \(streamingStatus.rawValue))...", source: "camera", level: "info")
            let waitStart = ContinuousClock.now
            while streamingStatus != .streaming {
                guard lifecycleID == captureLifecycle, cameraID == captureBurst else { throw CameraError.streamNotReady }
                if ContinuousClock.now - waitStart > .seconds(20) {
                    ErrorReporter.shared.report("Timed out waiting for streaming (stuck at \(streamingStatus.rawValue))", source: "camera", level: "error")
                    throw CameraError.streamNotReady
                }
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        guard lifecycleID == captureLifecycle, cameraID == captureBurst else { throw CameraError.streamNotReady }
        ErrorReporter.shared.report("Stream is live — capturing photo...", source: "camera", level: "info")

        // Capture from the running stream (from sample app line 158-159)
        let requestID = UUID()
        let photoData: Data = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.photoContinuation = continuation
                self.photoRequestID = requestID

                let success = streamSession.capturePhoto(format: .jpeg)
                if !success {
                    self.photoContinuation = nil
                    self.photoRequestID = nil
                    ErrorReporter.shared.report("capturePhoto(format:) returned false", source: "camera", level: "error")
                    continuation.resume(throwing: CameraError.captureFailed)
                    return
                }

                // Timeout safety
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if self.photoRequestID == requestID, let cont = self.photoContinuation {
                        self.photoContinuation = nil
                        self.photoRequestID = nil
                        ErrorReporter.shared.report("Photo capture timed out after 10s", source: "camera", level: "error")
                        cont.resume(throwing: CameraError.timeout)
                    }
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.photoRequestID == requestID else { return }
                self.endDeviceSession(throwing: CancellationError())
            }
        })

        captured = true
        // The defer detaches this camera on success, error, timeout or cancel.
        ErrorReporter.shared.report("Photo captured: \(photoData.count) bytes, stopping camera", source: "camera", level: "info")
        return photoData
    }

    /// Save photo to a dedicated "Glasses" album in Photos
    func saveToPhotoLibrary(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        saveToGlassesAlbum(image)
    }

    private nonisolated func saveToGlassesAlbum(_ image: UIImage) {
        let albumName = "Glasses"

        // Find or create the album, then save
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        if let album = albums.firstObject {
            addImage(image, to: album)
        } else {
            var albumPlaceholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                albumPlaceholder = request.placeholderForCreatedAssetCollection
            }) { success, error in
                if success, let placeholder = albumPlaceholder {
                    let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                    if let album = fetchResult.firstObject {
                        self.addImage(image, to: album)
                    }
                } else {
                    NSLog("[Camera] Failed to create Glasses album: \(error?.localizedDescription ?? "unknown")")
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
        }
    }

    private nonisolated func addImage(_ image: UIImage, to album: PHAssetCollection) {
        PHPhotoLibrary.shared().performChanges({
            let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            guard let placeholder = assetRequest.placeholderForCreatedAsset,
                  let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.addAssets([placeholder] as NSFastEnumeration)
        }) { success, error in
            if success {
                NSLog("[Camera] Photo saved to Glasses album")
            } else {
                NSLog("[Camera] Failed to save to Glasses album: \(error?.localizedDescription ?? "unknown")")
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }


    // MARK: - State Management

    private func updateStatusFromState(_ state: StreamState) {
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
