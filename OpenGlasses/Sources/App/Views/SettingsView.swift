import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var fastMode: Bool = UserDefaults.standard.bool(forKey: "fastMode")
    @State private var wakePhrase: String = Config.wakePhrase
    
    var body: some View {
        NavigationView {
            List {
                // Connection Status
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
                
                // Speed Toggle
                Section("Response Speed") {
                    Toggle(isOn: $fastMode) {
                        VStack(alignment: .leading) {
                            Text("Fast Mode")
                                .foregroundColor(Color(hex: "E1EFF3"))
                            Text(fastMode ? "Sonnet — faster, good for simple questions" : "Opus — slower, best for complex tasks")
                                .font(.caption)
                                .foregroundColor(Color(hex: "8EDCEF"))
                        }
                    }
                    .tint(Color(hex: "8EDCEF"))
                    .onChange(of: fastMode) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "fastMode")
                    }
                }
                
                // Wake Word
                Section("Wake Word") {
                    TextField("Wake phrase", text: $wakePhrase)
                        .foregroundColor(Color(hex: "E1EFF3"))
                        .onSubmit {
                            Config.setWakePhrase(wakePhrase)
                        }
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
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "8EDCEF"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
