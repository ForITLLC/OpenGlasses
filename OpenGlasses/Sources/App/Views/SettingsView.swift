import ForITCommon
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    // listeningEnabled is driven by appState.listeningEnabled (observable)
    @State private var speedMode: String
    @State private var apiKey: String
    @State private var userEmail: String
    @State private var selectedVoiceID: String
    @State private var voiceCatalog: BernardVoiceCatalog?
    @State private var isLoadingVoices = false
    @State private var voiceError: String?
    @State private var voiceUndo: VoiceSelectionUndo?

    private var isScreenshot: Bool {
        #if DEBUG
        OpenGlassesScreenshotFixture.isActive
        #else
        false
        #endif
    }

    init() {
        #if DEBUG
        let screenshot = OpenGlassesScreenshotFixture.isActive
        #else
        let screenshot = false
        #endif
        _speedMode = State(initialValue: screenshot ? "fast" : UserDefaults.standard.string(forKey: "speedMode") ?? "fast")
        _apiKey = State(initialValue: screenshot ? "" : UserDefaults.standard.string(forKey: "doloresAPIKey") ?? "")
        _userEmail = State(initialValue: screenshot ? "" : Config.userEmail)
        _selectedVoiceID = State(initialValue: screenshot ? "" : Config.bernardVoiceID)
    }

    var body: some View {
        List {
            // Account
            Section {
                HStack {
                    Image(systemName: "person.circle")
                        .foregroundColor(Color(hex: "8EDCEF"))
                    TextField("Email", text: $userEmail)
                        .forITField(on: .navy)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .onSubmit { if !isScreenshot { Config.setUserEmail(userEmail) } }
                }
                HStack {
                    Image(systemName: "key")
                        .foregroundColor(Color(hex: "8EDCEF"))
                    SecureField("API Key", text: $apiKey)
                        .forITField(on: .navy)
                        .onSubmit { if !isScreenshot { Config.setAPIKey(apiKey) } }
                }
                if isScreenshot || (apiKey.isEmpty && Config.doloresAPIKey.isEmpty) {
                    Text("No API key configured. Get one from your admin.")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if !apiKey.isEmpty {
                    Text("Using custom API key")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("Using default API key")
                        .font(.caption)
                        .foregroundColor(Color(hex: "8EDCEF").opacity(0.6))
                }
            } header: {
                Text("Account")
            }

            // Glasses
            Section("Glasses") {
                HStack {
                    Image(systemName: appState.isConnected ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.isConnected ? Color(hex: "8EDCEF") : Color(hex: "E1EFF3").opacity(0.4))
                    Text(appState.isConnected ? "Connected" : "Not Connected")
                        .foregroundColor(Color(hex: "E1EFF3"))
                }
                if let name = appState.glassesService.deviceName {
                    HStack {
                        Image(systemName: "eyeglasses")
                            .foregroundColor(Color(hex: "8EDCEF"))
                        Text(name)
                            .foregroundColor(Color(hex: "E1EFF3"))
                    }
                }
            }

            voiceSection

            // Response Speed
            Section {
                Picker("Speed", selection: $speedMode) {
                    Text("Haiku — fastest").tag("fastest")
                    Text("Sonnet — balanced").tag("fast")
                    Text("Opus — smartest").tag("opus")
                }
                .pickerStyle(.menu)
                .foregroundColor(Color(hex: "8EDCEF"))
                .onChange(of: speedMode) { _, newValue in
                    guard !isScreenshot else { return }
                    UserDefaults.standard.set(newValue, forKey: "speedMode")
                }
            } header: {
                Text("Response Speed")
            }

            // Listening Master Switch
            Section {
                Toggle(isOn: Binding(
                    get: { appState.listeningEnabled },
                    set: { if !isScreenshot { appState.setListeningEnabled($0) } }
                )) {
                    HStack {
                        Image(systemName: appState.listeningEnabled ? "ear.fill" : "ear.badge.waveform")
                        Text("Allow Meta voice launch")
                    }
                }
                .toggleStyle(.forITToggle(on: .navy))
            } footer: {
                Text("Say “Hey Meta, start ForIT Glasses.” Requires Meta beta setup.")
                    .foregroundColor(Color(hex: "E1EFF3").opacity(0.4))
            }

            FeedbackSection()

            // About
            Section("About") {
                HStack {
                    Text("Version")
                        .foregroundColor(Color(hex: "E1EFF3"))
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(Color(hex: "E1EFF3").opacity(0.5))
                }
                HStack {
                    Text("Powered by")
                        .foregroundColor(Color(hex: "E1EFF3"))
                    Spacer()
                    Text("ForIT AI")
                        .foregroundColor(Color(hex: "8EDCEF"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .forITScreenBackground()
        .feedbackDialogs()
        .preferredColorScheme(.dark)
        .onDisappear(perform: saveAccount)
        .task { await loadVoices() }
        .forITUndoBanner(voiceUndo) { change in
            ForITUndoBanner("Voice saved for your next reply.", undoHint: "Restores the previous voice", undo: {
                guard !isScreenshot else { return }
                // Another Settings window may already have changed this preference.
                guard Config.bernardVoiceID == change.after else {
                    voiceUndo = nil
                    return
                }
                Config.setBernardVoiceID(change.before)
                selectedVoiceID = change.before
                voiceUndo = nil
            }, dismiss: { voiceUndo = nil })
        }
    }

    private struct VoiceSelectionUndo: Equatable {
        let before: String
        let after: String
    }

    private var voiceChoices: [ForITChoiceOption<String>] {
        var choices = [ForITChoiceOption("", title: voiceCatalog.map { "Default — \($0.defaultVoiceName)" } ?? "Bernard's default",
                                         accessibilityIdentifier: "voice.default")]
        if let voiceCatalog {
            choices += voiceCatalog.voices.map {
                ForITChoiceOption($0.id, title: $0.name, accessibilityIdentifier: "voice.\($0.id)")
            }
            if !voiceCatalog.contains(selectedVoiceID) {
                choices.append(ForITChoiceOption(selectedVoiceID, title: "Saved voice (unavailable)",
                                                accessibilityIdentifier: "voice.unavailable"))
            }
        }
        return choices
    }

    private var voiceSelection: Binding<String> {
        Binding(get: { selectedVoiceID }, set: { newValue in
            guard !isScreenshot, let voiceCatalog, voiceCatalog.contains(newValue), newValue != selectedVoiceID else { return }
            let before = Config.bernardVoiceID
            Config.setBernardVoiceID(newValue)
            selectedVoiceID = newValue
            voiceUndo = VoiceSelectionUndo(before: before, after: newValue)
        })
    }

    private var voiceSection: some View {
        Section {
            if voiceCatalog != nil || isScreenshot {
                ForITChoicePicker("Voice", selection: voiceSelection, choices: voiceChoices, on: .navy,
                                  forceMenu: true, identifier: "voice.selection")
                    .disabled(isScreenshot)
            }
            if isLoadingVoices {
                ProgressView("Loading voices…")
            }
            if let voiceError {
                Text(voiceError)
                    .font(.caption)
                Button("Try again") { saveAccount(); Task { await loadVoices() } }
                    .buttonStyle(.forITText(on: .navy))
                    .disabled(isLoadingVoices)
            } else if let voiceCatalog, !voiceCatalog.contains(selectedVoiceID) {
                Text("Your saved voice is no longer available. Choose a voice for your next reply.")
                    .font(.caption)
            }
        } header: {
            Text("Bernard's Voice")
        } footer: {
            Text("Changes apply to the next spoken reply. Your choice is saved on this device.")
        }
    }

    @MainActor
    private func loadVoices() async {
        guard !isScreenshot, !isLoadingVoices else { return }
        isLoadingVoices = true
        voiceError = nil
        defer { isLoadingVoices = false }
        do {
            voiceCatalog = try await BernardVoiceCatalog.load()
        } catch is CancellationError {
            // Closing Settings doesn't invalidate its saved preference.
        } catch {
            guard !Task.isCancelled else { return }
            voiceError = error.localizedDescription
        }
    }

    /// The shared Settings sheet owns Done; save account edits when it closes.
    private func saveAccount() {
        guard !isScreenshot else { return }
        if !apiKey.isEmpty { Config.setAPIKey(apiKey) }
        Config.setUserEmail(userEmail)
    }
}
