import SwiftUI

struct AddModelView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedProvider: LLMProvider = .anthropic
    @State private var apiKey: String = ""
    @State private var model: String = LLMProvider.anthropic.defaultModel
    @State private var baseURL: String = LLMProvider.anthropic.defaultBaseURL

    let onAdd: (ModelConfig) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Quick Setup") {
                    Button("z.ai (subscription)") {
                        selectedProvider = .custom
                        name = "z.ai (subscription)"
                        baseURL = "https://api.z.ai/api/coding/paas/v4"
                        if model.isEmpty || model == LLMProvider.custom.defaultModel {
                            model = "glm-4.5"
                        }
                    }
                    Text("Auto-fills an OpenAI-compatible z.ai setup. Paste your z.ai subscription API key and adjust model if needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Display Name") {
                    TextField("e.g. Claude Sonnet, GPT-4o", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Provider") {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) { _, newProvider in
                        model = newProvider.defaultModel
                        baseURL = newProvider.defaultBaseURL
                        if name.isEmpty {
                            name = newProvider.displayName
                        }
                    }
                }

                Section("Configuration") {
                    SecureField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Model", text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if selectedProvider == .custom {
                        TextField("Base URL", text: $baseURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.caption)
                    }

                    Text(providerHelpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let config = ModelConfig(
                            id: UUID().uuidString,
                            name: name.isEmpty ? selectedProvider.displayName : name,
                            provider: selectedProvider.rawValue,
                            apiKey: apiKey,
                            model: model,
                            baseURL: baseURL
                        )
                        onAdd(config)
                        dismiss()
                    }
                    .disabled(apiKey.isEmpty)
                }
            }
        }
    }

    private var providerHelpText: String {
        switch selectedProvider {
        case .anthropic: return "console.anthropic.com"
        case .openai: return "platform.openai.com"
        case .gemini: return "aistudio.google.com"
        case .groq: return "console.groq.com"
        case .custom: return "Any OpenAI-compatible API endpoint (e.g. z.ai: https://api.z.ai/api/coding/paas/v4)"
        }
    }
}
