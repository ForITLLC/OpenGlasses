import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var speedMode: String = UserDefaults.standard.string(forKey: "speedMode") ?? "fast"
    @State private var enabledWakePhrases: Set<String> = Set(Config.enabledWakePhrases)
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "doloresAPIKey") ?? ""
    @State private var userEmail: String = Config.userEmail

    var body: some View {
        NavigationView {
            List {
                // Account
                Section {
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundColor(Color(hex: "8EDCEF"))
                        TextField("Email", text: $userEmail)
                            .foregroundColor(Color(hex: "E1EFF3"))
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .onSubmit { Config.setUserEmail(userEmail) }
                    }
                    HStack {
                        Image(systemName: "key")
                            .foregroundColor(Color(hex: "8EDCEF"))
                        SecureField("API Key", text: $apiKey)
                            .foregroundColor(Color(hex: "E1EFF3"))
                            .onSubmit { Config.setAPIKey(apiKey) }
                    }
                    if apiKey.isEmpty && Config.doloresAPIKey.isEmpty {
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
                        UserDefaults.standard.set(newValue, forKey: "speedMode")
                    }
                } header: {
                    Text("Response Speed")
                }

                // Wake Words (multi-select)
                Section {
                    ForEach(Config.availableWakePhrases, id: \.self) { phrase in
                        Button {
                            if enabledWakePhrases.contains(phrase) {
                                if enabledWakePhrases.count > 1 {
                                    enabledWakePhrases.remove(phrase)
                                }
                            } else {
                                enabledWakePhrases.insert(phrase)
                            }
                            Config.setEnabledWakePhrases(Array(enabledWakePhrases))
                        } label: {
                            HStack {
                                Text(phrase.split(separator: " ").map { $0.capitalized }.joined(separator: " "))
                                    .foregroundColor(Color(hex: "E1EFF3"))
                                Spacer()
                                if enabledWakePhrases.contains(phrase) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color(hex: "8EDCEF"))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Wake Words")
                } footer: {
                    Text("Select one or more. The app listens for all enabled phrases simultaneously.")
                        .foregroundColor(Color(hex: "E1EFF3").opacity(0.4))
                }

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
            .background(Color(hex: "0A1A26"))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        // Save on dismiss
                        if !apiKey.isEmpty { Config.setAPIKey(apiKey) }
                        Config.setUserEmail(userEmail)
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "8EDCEF"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
