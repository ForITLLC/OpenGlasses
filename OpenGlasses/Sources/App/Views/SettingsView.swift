import ForITCommon
import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    // listeningEnabled is driven by appState.listeningEnabled (observable)
    @State private var speedMode: String
    @ObservedObject private var account = AppAccount.shared
    @State private var windowSource = AuthWindowReader.WindowSource()
    @State private var selectedVoiceID: String
    @State private var voiceCatalog: BernardVoiceCatalog?
    @State private var isLoadingVoices = false
    @State private var voiceError: String?
    @State private var voiceUndo: VoiceSelectionUndo?
    @State private var voiceLoadGeneration = UUID()

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
        _selectedVoiceID = State(initialValue: screenshot ? "" : Config.bernardVoiceID)
    }

    var body: some View {
        List {
            // Account
            Section {
                LabeledContent("ForIT account", value: isScreenshot ? "ForIT account" : account.email ?? "Signed out")
                if account.signedIn {
                    Button("Sign out") { account.confirmingSignOut = true }
                } else {
                    Button { if !isScreenshot { account.signInAccount(from: windowSource.window) } } label: { ForITSignInLabel() }
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
            if account.signedIn && !isScreenshot {
                MuseConnectionSection(windowSource: windowSource)
            }

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
                Text("Say “Hey Meta, start Bernard.” Requires Meta beta setup.")
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
        .background(AuthWindowReader(source: windowSource))
        .scrollContentBackground(.hidden)
        .forITScreenBackground()
        .feedbackDialogs()
        .preferredColorScheme(.dark)
        .task(id: account.email) {
            voiceCatalog = nil
            voiceUndo = nil
            await loadVoices()
        }
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
                Button("Try again") { Task { await loadVoices() } }
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
        guard !isScreenshot else { return }
        let generation = UUID()
        voiceLoadGeneration = generation
        isLoadingVoices = true
        voiceError = nil
        defer { if voiceLoadGeneration == generation { isLoadingVoices = false } }
        do {
            let catalog = try await BernardVoiceCatalog.load()
            guard !Task.isCancelled, voiceLoadGeneration == generation else { return }
            voiceCatalog = catalog
        } catch is CancellationError {
            // Closing Settings doesn't invalidate its saved preference.
        } catch {
            guard !Task.isCancelled, voiceLoadGeneration == generation else { return }
            voiceError = error.localizedDescription
        }
    }

}
