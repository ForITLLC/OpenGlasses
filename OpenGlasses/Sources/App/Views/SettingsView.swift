import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var wakeWordInput = Config.wakePhrase
    @State private var wakeWordAltsInput = Config.alternativeWakePhrases.joined(separator: ", ")
    @State private var selectedPreset = Config.wakePhrase
    @State private var elevenLabsKeyInput = Config.elevenLabsAPIKey
    @State private var selectedVoice = Config.elevenLabsVoiceId
    @State private var systemPromptInput = Config.systemPrompt

    // Model configs editing
    @State private var modelConfigs: [ModelConfig] = Config.savedModels
    @State private var editingModel: ModelConfig? = nil
    @State private var showAddModel = false

    // OpenClaw settings
    @State private var openClawEnabled = Config.openClawEnabled
    @State private var openClawConnectionMode = Config.openClawConnectionMode
    @State private var openClawLanHost = Config.openClawLanHost
    @State private var openClawPort = String(Config.openClawPort)
    @State private var openClawTunnelHost = Config.openClawTunnelHost
    @State private var openClawGatewayToken = Config.openClawGatewayToken
    @State private var openClawTestStatus: String = ""

    private let mutedOrange = Color(red: 0.78, green: 0.56, blue: 0.32)
    private let mutedRed = Color(red: 0.75, green: 0.30, blue: 0.30)
    private let mutedBlue = Color(red: 0.38, green: 0.52, blue: 0.68)
    private let mutedGreen = Color(red: 0.35, green: 0.62, blue: 0.45)

    private let wakeWordPresets = [
        "hey dolores", "hey claude", "hey jarvis", "hey rayban", "hey computer", "hey assistant"
    ]

    var body: some View {
        NavigationView {
            Form {
                // MARK: Wake Word
                Section("Wake Word") {
                    Picker("Preset", selection: $selectedPreset) {
                        Text("Hey Dolores").tag("hey dolores")
                        Text("Hey Claude").tag("hey claude")
                        Text("Hey Jarvis").tag("hey jarvis")
                        Text("Hey Rayban").tag("hey rayban")
                        Text("Hey Computer").tag("hey computer")
                        Text("Hey Assistant").tag("hey assistant")
                        if !wakeWordPresets.contains(wakeWordInput.lowercased()) && !wakeWordInput.isEmpty {
                            Text("Custom: \(wakeWordInput)").tag(wakeWordInput.lowercased())
                        }
                    }
                    .onChange(of: selectedPreset) { _, newValue in
                        wakeWordInput = newValue
                        let defaults = Config.defaultAlternativesForPhrase(newValue)
                        wakeWordAltsInput = defaults.joined(separator: ", ")
                    }

                    TextField("Custom wake phrase", text: $wakeWordInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: wakeWordInput) { _, newValue in
                            if !wakeWordPresets.contains(newValue.lowercased()) {
                                selectedPreset = newValue.lowercased()
                            }
                        }

                    if wakeWordInput.split(separator: " ").count < 2 {
                        Text("Use at least 2 words (e.g. \"hey jarvis\") to avoid false triggers")
                            .font(.caption)
                            .foregroundColor(mutedOrange)
                    }

                    TextField("Alternative spellings (comma separated)", text: $wakeWordAltsInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.caption)

                    Text("Alternatives catch misrecognitions, e.g. \"hey cloud\" for \"hey claude\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: AI Models
                Section {
                    ForEach(modelConfigs) { model in
                        Button {
                            editingModel = model
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                    HStack(spacing: 4) {
                                        Text(model.llmProvider.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if !model.apiKey.isEmpty {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "exclamationmark.circle")
                                                .font(.caption2)
                                                .foregroundColor(mutedOrange)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        modelConfigs.remove(atOffsets: indexSet)
                    }

                    Button {
                        showAddModel = true
                    } label: {
                        Label("Add Model", systemImage: "plus.circle.fill")
                            .foregroundColor(mutedBlue)
                    }
                } header: {
                    Text("AI Models")
                } footer: {
                    Text("Configure multiple models and switch between them on the main screen")
                }

                // MARK: System Prompt
                Section {
                    TextEditor(text: $systemPromptInput)
                        .font(.caption)
                        .frame(minHeight: 150)

                    Button("Reset to Default") {
                        systemPromptInput = Config.defaultSystemPrompt
                    }
                    .font(.caption)
                    .foregroundColor(mutedRed)
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("This prompt is sent with every message to guide the AI's behaviour")
                }

                // MARK: ElevenLabs
                Section("ElevenLabs Voice (Optional)") {
                    SecureField("ElevenLabs API key", text: $elevenLabsKeyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Picker("Voice", selection: $selectedVoice) {
                        Text("Rachel (warm female)").tag("21m00Tcm4TlvDq8ikWAM")
                        Text("Bella (young female)").tag("EXAVITQu4vr4xnSDxMaL")
                        Text("Adam (deep male)").tag("pNInz6obpgDQGcFmaJgB")
                        Text("Antoni (friendly male)").tag("ErXwobaYiN019PkySvjV")
                        Text("Daniel (British male)").tag("onwK4e9ZLuTAKqWW03F9")
                    }

                    Text("Free tier: 10k chars/month at elevenlabs.io")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if elevenLabsKeyInput.isEmpty {
                        Text("Without ElevenLabs, iOS built-in voice is used")
                            .font(.caption)
                            .foregroundColor(mutedOrange)
                    }
                }

                // MARK: OpenClaw
                Section {
                    Toggle("Enable OpenClaw", isOn: $openClawEnabled)

                    if openClawEnabled {
                        SecureField("Gateway Token", text: $openClawGatewayToken)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Picker("Connection", selection: $openClawConnectionMode) {
                            ForEach(OpenClawConnectionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        if openClawConnectionMode != .tunnel {
                            TextField("LAN Host", text: $openClawLanHost)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.caption)

                            TextField("Port", text: $openClawPort)
                                .keyboardType(.numberPad)
                                .font(.caption)
                        }

                        if openClawConnectionMode != .lan {
                            TextField("Tunnel Host", text: $openClawTunnelHost)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.caption)
                        }

                        Button {
                            testOpenClawConnection()
                        } label: {
                            HStack {
                                Text("Test Connection")
                                if !openClawTestStatus.isEmpty {
                                    Spacer()
                                    Text(openClawTestStatus)
                                        .font(.caption)
                                        .foregroundColor(openClawTestStatus.contains("Connected") ? mutedGreen : mutedRed)
                                }
                            }
                        }
                    }
                } header: {
                    Text("OpenClaw Agent Gateway")
                } footer: {
                    Text("Connect to OpenClaw on your Mac for 56+ tools: messaging, web search, smart home, and more")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { saveSettings() }
                }
            }
            .sheet(item: $editingModel) { model in
                ModelEditorView(model: model) { updated in
                    if let idx = modelConfigs.firstIndex(where: { $0.id == updated.id }) {
                        modelConfigs[idx] = updated
                    }
                }
            }
            .sheet(isPresented: $showAddModel) {
                AddModelView { newModel in
                    modelConfigs.append(newModel)
                }
            }
        }
    }

    // MARK: - Save Settings

    private func saveSettings() {
        Config.setWakePhrase(wakeWordInput)
        let alts = wakeWordAltsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        Config.setAlternativeWakePhrases(alts)

        Config.setSavedModels(modelConfigs)

        if !modelConfigs.contains(where: { $0.id == Config.activeModelId }) {
            if let first = modelConfigs.first {
                Config.setActiveModelId(first.id)
            }
        }
        appState.llmService.refreshActiveModel()

        Config.setSystemPrompt(systemPromptInput)

        Config.setElevenLabsAPIKey(elevenLabsKeyInput)
        Config.setElevenLabsVoiceId(selectedVoice)

        Config.setOpenClawEnabled(openClawEnabled)
        Config.setOpenClawConnectionMode(openClawConnectionMode)
        Config.setOpenClawLanHost(openClawLanHost)
        if let port = Int(openClawPort) {
            Config.setOpenClawPort(port)
        }
        Config.setOpenClawTunnelHost(openClawTunnelHost)
        Config.setOpenClawGatewayToken(openClawGatewayToken)
        appState.openClawBridge.clearCachedEndpoint()

        dismiss()

        if appState.currentMode == .direct {
            Task {
                appState.wakeWordService.stopListening()
                try? await Task.sleep(nanoseconds: 300_000_000)
                try? await appState.wakeWordService.startListening()
            }
        }
    }

    private func testOpenClawConnection() {
        openClawTestStatus = "Testing..."
        Config.setOpenClawEnabled(openClawEnabled)
        Config.setOpenClawConnectionMode(openClawConnectionMode)
        Config.setOpenClawLanHost(openClawLanHost)
        if let port = Int(openClawPort) {
            Config.setOpenClawPort(port)
        }
        Config.setOpenClawTunnelHost(openClawTunnelHost)
        Config.setOpenClawGatewayToken(openClawGatewayToken)

        appState.openClawBridge.clearCachedEndpoint()
        Task {
            await appState.openClawBridge.checkConnection()
            switch appState.openClawBridge.connectionState {
            case .connected:
                let via = appState.openClawBridge.resolvedConnection?.label ?? "unknown"
                openClawTestStatus = "Connected via \(via)"
            case .unreachable(let msg):
                openClawTestStatus = "Unreachable: \(msg)"
            case .notConfigured:
                openClawTestStatus = "Not configured"
            case .checking:
                openClawTestStatus = "Checking..."
            }
        }
    }
}
