import SwiftUI

struct ModelPickerSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let mutedPurple = Color(red: 0.55, green: 0.40, blue: 0.68)
    private let mutedGreen = Color(red: 0.35, green: 0.62, blue: 0.45)

    var body: some View {
        NavigationView {
            List {
                let models = Config.savedModels
                let activeId = Config.activeModelId

                if models.isEmpty {
                    Text("No models configured. Add one in Settings.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(models) { model in
                        Button {
                            Config.setActiveModelId(model.id)
                            appState.llmService.clearHistory()
                            appState.llmService.refreshActiveModel()
                            
                            if appState.currentMode == .geminiLive {
                                appState.switchMode(to: .direct)
                            }
                            
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                    Text("\(model.llmProvider.displayName) \u{2022} \(model.model)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if model.id == activeId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(mutedGreen)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
