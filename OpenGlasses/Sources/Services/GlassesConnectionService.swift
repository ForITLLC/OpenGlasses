import Combine
import Foundation
import MWDATCore

/// Service for connecting to Ray-Ban Meta smart glasses
/// Uses Meta Wearables Device Access Toolkit (MWDAT)
@MainActor
class GlassesConnectionService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "Not connected"
    @Published var deviceName: String?
    @Published var batteryLevel: Int?

    private var devicesListenerToken: (any AnyListenerToken)?
    private var connectedDeviceId: DeviceIdentifier?
    private var deviceStateToken: (any AnyListenerToken)?

    init() {
        observeDevices()
    }

    private func observeDevices() {
        // `Wearables.shared` fatalErrors when configure() failed — stay inert instead.
        guard WearablesRuntime.isConfigured else {
            connectionStatus = "Meta SDK not registered"
            return
        }
        devicesListenerToken = Wearables.shared.addDevicesListener { [weak self] deviceIds in
            Task { @MainActor in
                self?.handleDevicesChanged(deviceIds)
            }
        }
        handleDevicesChanged(Wearables.shared.devices)
    }

    private func handleDevicesChanged(_ deviceIds: [DeviceIdentifier]) {
        // Defense in depth. Today this is only reachable from the listener registered
        // in observeDevices(), which is already behind the guard — so its safety rests
        // on call-graph reasoning rather than anything local, and `deviceForIdentifier`
        // traps on an unconfigured SDK. Guard here too so a future direct caller is safe.
        guard WearablesRuntime.isConfigured else { return }

        let previousToken = deviceStateToken
        deviceStateToken = nil
        Task { await previousToken?.cancel() }
        if let firstId = deviceIds.first,
           let device = Wearables.shared.deviceForIdentifier(firstId) {
            connectedDeviceId = firstId
            deviceName = device.name
            applyDeviceState(linkState: device.linkState, battery: device.batteryLevel)
            deviceStateToken = device.addDeviceStateListener { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.connectedDeviceId == firstId else { return }
                    self.applyDeviceState(linkState: state.linkState, battery: state.batteryLevel)
                }
            }
        } else {
            connectedDeviceId = nil
            isConnected = false
            deviceName = nil
            batteryLevel = nil
            connectionStatus = "Disconnected"
        }
    }

    private func applyDeviceState(linkState: LinkState, battery: Int?) {
        isConnected = linkState == .connected
        batteryLevel = battery
        switch linkState {
        case .connected: connectionStatus = "Connected to \(deviceName ?? "glasses")"
        case .connecting: connectionStatus = "Connecting to \(deviceName ?? "glasses")"
        case .disconnected: connectionStatus = "Disconnected"
        @unknown default: connectionStatus = "Waiting for glasses"
        }
    }

    func connect() async {
        guard WearablesRuntime.isConfigured else {
            connectionStatus = "Meta SDK not registered"
            return
        }
        connectionStatus = "Registering..."
        let stateBefore = Wearables.shared.registrationState
        print("📋 Registration state before: \(stateBefore)")

        do {
            try await Wearables.shared.startRegistration()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let stateAfter = Wearables.shared.registrationState
            print("✅ startRegistration() succeeded, state: \(stateAfter)")
            connectionStatus = stateAfter.rawValue >= 3
                ? "Waiting for device..."
                : "Complete authorization in Meta AI app"
        } catch {
            print("❌ startRegistration() failed: \(error)")
            connectionStatus = "Connection failed: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        let token = deviceStateToken
        deviceStateToken = nil
        Task { await token?.cancel() }
        connectedDeviceId = nil
        isConnected = false
        deviceName = nil
        batteryLevel = nil
        connectionStatus = "Disconnected"
    }
}

// MARK: - Errors
enum GlassesError: LocalizedError {
    case connectionFailed(String)
    case notConnected
    case streamingFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .notConnected: return "Glasses not connected"
        case .streamingFailed(let msg): return "Streaming failed: \(msg)"
        }
    }
}
