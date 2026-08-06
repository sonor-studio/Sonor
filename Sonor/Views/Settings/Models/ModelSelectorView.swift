import SwiftUI
import Hub

struct ModelSelectorView: View {
    @ObservedObject var manager = ModelManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showUninstallConfirmation = false
    @State private var modelToUninstall: ModelsSettingsView.ModelType? = nil
    
    // Group MLX models by family
    var groupedMLXModels: [(family: String, models: [ModelManager.MLXModel])] {
        let dict = Dictionary(grouping: manager.availableMLXModels, by: { $0.family })
        return dict.map { (family: $0.key, models: $0.value) }.sorted(by: { $0.family < $1.family })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(t("Select Transcription Model"))
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: { manager.showModelSelector = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.bottom, 10)
            
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Available Models Grouped
                    VStack(alignment: .leading, spacing: 16) {
                        Text(t("Available Models"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        ForEach(groupedMLXModels, id: \.family) { group in
                            CustomDisclosureGroup(
                                title: group.family,
                                description: t(ModelManager.shared.modelFamilyDescriptions[group.family] ?? ""),
                                modelsCount: group.models.count
                            ) {
                                VStack(spacing: 12) {
                                    ForEach(group.models) { model in
                                        RichModelCard(
                                            title: model.name,
                                            description: t(model.description),
                                            weight: model.weight,
                                            languages: model.languages,
                                            accuracy: model.accuracy,
                                            speed: model.speed,
                                            company: model.company,
                                            parameters: model.parameters,
                                            supportedLanguagesList: model.supportedLanguagesList,
                                            state: manager.mlxStates[model.id] ?? .notDownloaded,
                                            progressText: manager.activeMLXDownloadTexts[model.id],
                                            isActive: manager.selectedMLXModelId == model.id && TranscriptionManager.shared.currentEngineType == .mlx,
                                            onSetActive: {
                                                manager.selectedMLXModelId = model.id
                                                TranscriptionManager.shared.setEngineType(.mlx)
                                                manager.showModelSelector = false
                                            },
                                            onDownload: { manager.downloadMLXModel(modelId: model.id) },
                                            onPause: { manager.pauseMLXDownload(modelId: model.id) },
                                            onCancel: { manager.cancelMLXDownload(modelId: model.id) },
                                            onUninstall: {
                                                self.modelToUninstall = .mlx(id: model.id)
                                                self.showUninstallConfirmation = true
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        
                        CustomDisclosureGroup(
                            title: "Whisper",
                            description: t(ModelManager.shared.modelFamilyDescriptions["Whisper"] ?? ""),
                            modelsCount: manager.availableWhisperModels.count
                        ) {
                            VStack(spacing: 12) {
                                ForEach(manager.availableWhisperModels) { model in
                                    RichModelCard(
                                        title: model.name,
                                        description: t(model.description),
                                        weight: model.weight,
                                        languages: model.languages,
                                        accuracy: model.accuracy,
                                        speed: model.speed,
                                        company: model.company,
                                        parameters: model.parameters,
                                        supportedLanguagesList: model.supportedLanguagesList,
                                        state: manager.whisperStates[model.id] ?? .notDownloaded,
                                        isActive: manager.selectedWhisperModelId == model.id && TranscriptionManager.shared.currentEngineType == .whisper,
                                        onSetActive: {
                                            manager.selectedWhisperModelId = model.id
                                            TranscriptionManager.shared.setEngineType(.whisper)
                                            manager.showModelSelector = false
                                        },
                                        onDownload: { manager.downloadWhisper(modelId: model.id) },
                                        onPause: { manager.pauseWhisperDownload(modelId: model.id) },
                                        onCancel: { manager.cancelWhisperDownload(modelId: model.id) },
                                        onUninstall: {
                                            self.modelToUninstall = .whisper(id: model.id)
                                            self.showUninstallConfirmation = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 16)
            }
        }
        .padding(24)
        .frame(width: 700, height: 550)
        .preferredColorScheme(colorScheme)
        .alert(isPresented: $showUninstallConfirmation) {
            Alert(
                title: Text(t("Uninstall Model")),
                message: Text(t("Are you sure you want to uninstall this model?")),
                primaryButton: .destructive(Text(t("Uninstall"))) {
                    if let model = modelToUninstall {
                        switch model {
                        case .whisper(let id):
                            manager.uninstallWhisper(modelId: id)
                        case .mlx(let id):
                            manager.uninstallMLXModel(modelId: id)
                        case .gemma:
                            manager.uninstallGemma()
                        }
                    }
                },
                secondaryButton: .cancel(Text(t("Cancel")))
            )
        }
    }
}
