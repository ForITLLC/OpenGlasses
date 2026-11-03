import Combine
import Foundation
import MWDATCore

/// App-scoped DAT 1.x voice-launch channel. Meta owns the wake phrase; this
/// service does not record audio or run a second wake-word recognizer.
/// Voice Invocations is currently available in Meta development/beta channels.
@MainActor
final class MetaVoiceInvocationService: ObservableObject {
    @Published private(set) var lastError: String?

    private var onLaunch: (@MainActor () async throws -> Void)?
    private var stream: VoiceInvocationsStream?
    private var invocationToken: (any AnyListenerToken)?
    private var errorToken: (any AnyListenerToken)?
    private var rosterToken: (any AnyListenerToken)?
    private var deviceTokens: [any AnyListenerToken] = []
    private var registrationTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var listeningOn: DeviceIdentifier?
    private var generation = UUID()
    private var enabled = false
    private var handlingLaunch: UUID?
    private var retryDelay: UInt64 = 500_000_000

    func start(onLaunch: @escaping @MainActor () async throws -> Void) {
        self.onLaunch = onLaunch
        guard !enabled else { return }
        guard WearablesRuntime.isConfigured else {
            lastError = "Meta SDK not registered"
            return
        }
        enabled = true
        let lifecycle = generation
        rosterToken = Wearables.shared.addDevicesListener { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == lifecycle else { return }
                self.observeDeviceLinks()
            }
        }
        observeDeviceLinks()
        registrationTask = Task { @MainActor [weak self] in
            for await _ in Wearables.shared.registrationStateStream() {
                guard let self, self.generation == lifecycle else { return }
                self.refreshChannel()
            }
        }
    }

    func stop() {
        enabled = false
        generation = UUID()
        handlingLaunch = nil
        registrationTask?.cancel()
        registrationTask = nil
        retryTask?.cancel()
        retryTask = nil
        stream?.stop()
        stream = nil
        listeningOn = nil
        let tokens = [invocationToken, errorToken, rosterToken].compactMap { $0 } + deviceTokens
        invocationToken = nil
        errorToken = nil
        rosterToken = nil
        deviceTokens = []
        Task { for token in tokens { await token.cancel() } }
        onLaunch = nil
    }

    /// DAT has no public `isDATUrl` helper in 1.0.1. Match the SDK's configured
    /// callback scheme locally, keeping ForIT sign-in and unrelated links out.
    static func isDATURL(_ url: URL, bundle: Bundle = .main) -> Bool {
        guard let config = bundle.object(forInfoDictionaryKey: "MWDAT") as? [String: Any],
              let callback = config["AppLinkURLScheme"] as? String,
              let configuredScheme = URL(string: callback)?.scheme,
              let incomingScheme = url.scheme else { return false }
        return incomingScheme.caseInsensitiveCompare(configuredScheme) == .orderedSame
    }

    /// Used for both cold and warm URL entry. The SDK consumes the URL once;
    /// launch completion is acknowledged separately on `invocationsPublisher`.
    func handleURL(_ url: URL) async throws -> Bool {
        guard Self.isDATURL(url), WearablesRuntime.isConfigured else { return false }
        let handled = try await Wearables.shared.handleUrl(url)
        if enabled { observeDeviceLinks() }
        return handled
    }

    private func observeDeviceLinks() {
        guard enabled, WearablesRuntime.isConfigured else { return }
        let previous = deviceTokens
        deviceTokens = []
        Task { for token in previous { await token.cancel() } }
        let lifecycle = generation
        for identifier in Wearables.shared.devices {
            guard let device = Wearables.shared.deviceForIdentifier(identifier) else { continue }
            let token = device.addDeviceStateListener { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == lifecycle else { return }
                    self.refreshChannel()
                }
            }
            deviceTokens.append(token)
        }
        refreshChannel()
    }

    private func refreshChannel() {
        guard enabled, WearablesRuntime.isConfigured else { return }
        guard Wearables.shared.registrationState == .registered,
              let identifier = Wearables.shared.devices.first(where: {
                  Wearables.shared.deviceForIdentifier($0)?.linkState == .connected
              }) else {
            stream?.stop()
            listeningOn = nil
            return
        }
        guard listeningOn != identifier else { return }
        do {
            if stream == nil {
                let channel = try VoiceInvocationsStream(wearables: Wearables.shared)
                stream = channel
                let lifecycle = generation
                invocationToken = channel.invocationsPublisher.listen { [weak self] invocation in
                    guard let launch = invocation as? LaunchApp else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == lifecycle else {
                            _ = await launch.responseHandle.sendFailure(actionOutput: nil)
                            return
                        }
                        await self.handleLaunch(launch)
                    }
                }
                errorToken = channel.errorPublisher.listen { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == lifecycle else { return }
                        self.lastError = error.localizedDescription
                        self.stream?.stop()
                        self.listeningOn = nil
                        self.scheduleRetry()
                    }
                }
            }
            try stream?.start(deviceIdentifier: identifier)
            listeningOn = identifier
            lastError = nil
            retryDelay = 500_000_000
        } catch {
            listeningOn = nil
            lastError = error.localizedDescription
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard enabled, retryTask == nil else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30_000_000_000)
        let lifecycle = generation
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, self.generation == lifecycle else { return }
            self.retryTask = nil
            self.refreshChannel()
        }
    }

    /// One SDK request gets exactly one completion attempt. Starting the actual
    /// listening flow may fail (for example denied microphone access), in which
    /// case Meta receives failure rather than a successful launch claim.
    func handleLaunch(_ launch: LaunchApp) async {
        guard handlingLaunch == nil, let onLaunch else {
            _ = await launch.responseHandle.sendFailure(actionOutput: nil)
            return
        }
        let lifecycle = generation
        let invocation = UUID()
        handlingLaunch = invocation
        defer {
            if handlingLaunch == invocation { handlingLaunch = nil }
        }
        do {
            try await onLaunch()
            // Stop may run while permission or microphone startup is suspended.
            // A later recording belongs to the next lifecycle, not this launch.
            guard generation == lifecycle else {
                _ = await launch.responseHandle.sendFailure(actionOutput: nil)
                return
            }
            let delivered = await launch.responseHandle.sendSuccess(actionOutput: nil)
            guard generation == lifecycle else { return }
            if !delivered { lastError = "The launch reply did not reach Meta." }
        } catch {
            guard generation == lifecycle else {
                _ = await launch.responseHandle.sendFailure(actionOutput: nil)
                return
            }
            lastError = error.localizedDescription
            let delivered = await launch.responseHandle.sendFailure(actionOutput: nil)
            guard generation == lifecycle else { return }
            if !delivered { lastError = "The launch failed and its reply did not reach Meta." }
        }
    }
}
