import SwiftUI

struct ModelEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedProvider: LLMProvider
    @State private var apiKey: String
    @State private var model: String
    @State private var baseURL: String

    let modelId: String
    let onSave: (ModelConfig) -> Void

    init(model config: ModelConfig, onSave: @escaping (ModelConfig) -> Void) {
        self.modelId = config.id
        self.onSave = onSave
        _name = State(initialValue: config.name)
        _selectedProvider = State(initialValue: config.llmProvider)
        _apiKey = State(initialValue: config.apiKey)
        _model = State(initialValue: config.model)
        _baseURL = State(initialValue: config.baseURL)
    }

    var body: some View {
        NavigationView {
            Form {
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
                        baseURL = newProvider.defaultBaseURL
                        if model.isEmpty || LLMProvider.allCases.contains(where: { $0.defaultModel == model }) {
                            model = newProvider.defaultModel
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
            .navigationTitle("Edit Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let updated = ModelConfig(
                            id: modelId,
                            name: name.isEmpty ? selectedProvider.displayName : name,
                            provider: selectedProvider.rawValue,
                            apiKey: apiKey,
                            model: model,
                            baseURL: baseURL
                        )
                        onSave(updated)
                        dismiss()
                    }
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
        case .custom: return "Any OpenAI-compatible API endpoint"
        }
    }
}
