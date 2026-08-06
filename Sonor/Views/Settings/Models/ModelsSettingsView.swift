import SwiftUI
import Hub

struct ModelsSettingsView: View {
    @ObservedObject var manager = ModelManager.shared
    @ObservedObject var transcriptionManager = TranscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showUninstallConfirmation = false
    @State private var modelToUninstall: ModelType? = nil
    
    var activeOrDownloadingWhisperModels: [ModelManager.WhisperModel] {
        manager.availableWhisperModels.filter { model in
            guard let state = manager.whisperStates[model.id] else { return false }
            switch state {
            case .notDownloaded: return false
            default: return true
            }
        }
    }

    var activeOrDownloadingMLXModels: [ModelManager.MLXModel] {
        manager.availableMLXModels.filter { model in
            guard let state = manager.mlxStates[model.id] else { return false }
            switch state {
            case .notDownloaded: return false
            default: return true
            }
        }
    }

    var activeMLXFamilies: [String: [ModelManager.MLXModel]] {
        Dictionary(grouping: activeOrDownloadingMLXModels, by: { $0.family })
    }

    var activeWhisperFamilies: [String: [ModelManager.WhisperModel]] {
        Dictionary(grouping: activeOrDownloadingWhisperModels, by: { _ in "Whisper" })
    }

    var allActiveFamilies: [String] {
        Array(Set(activeMLXFamilies.keys).union(activeWhisperFamilies.keys)).sorted()
    }

    enum ModelType {
        case whisper(id: String)
        case mlx(id: String)
        case gemma
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                Text(t("Models"))
                    .font(.system(size: 28, weight: .bold))
            }
            Text(t("Manage the AI models used by Sonor for transcription and text processing."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
            VStack(spacing: 20) {
                // Transcription Models Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(t("Transcription Models"))
                            .font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Button(action: { manager.showModelSelector = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text(t("Add Model"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(colorScheme == .dark ? Color.white : Color.black)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Apple Speech Model
                    ModelCard(
                        title: "Apple Speech (System)",
                        description: t("Native speech recognition provided by macOS. Requires microphone permission. Does not require downloading model files."),
                        state: .downloaded,
                        isActive: transcriptionManager.currentEngineType == .appleSpeech,
                        onSetActive: {
                            transcriptionManager.setEngineType(.appleSpeech)
                        },
                        onDownload: { },
                        onCancel: { },
                        onUninstall: nil
                    )
                    
                    // Core ML Mock / MLX (if not downloaded)
                    if activeOrDownloadingWhisperModels.isEmpty && manager.availableMLXModels.filter({ manager.mlxStates[$0.id] == .downloaded }).isEmpty {
                        Text(t("No transcription models downloaded. Click 'Add Model' to download one."))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 10)
                    }
                    
                    ForEach(allActiveFamilies, id: \.self) { family in
                        Text(t(family))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                        
                        if let mlxModels = activeMLXFamilies[family] {
                            ForEach(mlxModels) { model in
                                let state = manager.mlxStates[model.id] ?? .notDownloaded
                                if state.isDownloading || state.isPaused {
                                    ActiveDownloadCard(
                                        title: model.name,
                                        descriptionText: t(model.description),
                                        state: state,
                                        stats: manager.mlxDownloadStats[model.id],
                                        onPause: { manager.pauseMLXDownload(modelId: model.id) },
                                        onResume: { manager.downloadMLXModel(modelId: model.id) },
                                        onCancel: { manager.cancelMLXDownload(modelId: model.id) }
                                    )
                                } else {
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
                                        state: state,
                                        progressText: manager.activeMLXDownloadTexts[model.id],
                                        isActive: manager.selectedMLXModelId == model.id && transcriptionManager.currentEngineType == .mlx,
                                        isExpandable: true,
                                        onSetActive: {
                                            manager.selectedMLXModelId = model.id
                                            transcriptionManager.setEngineType(.mlx)
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
                        
                        if let whisperModels = activeWhisperFamilies[family] {
                            ForEach(whisperModels) { model in
                                let state = manager.whisperStates[model.id] ?? .notDownloaded
                                if state.isDownloading || state.isPaused {
                                    ActiveDownloadCard(
                                        title: model.name,
                                        descriptionText: t(model.description),
                                        state: state,
                                        stats: manager.whisperDownloadStats[model.id],
                                        onPause: { manager.pauseWhisperDownload(modelId: model.id) },
                                        onResume: { manager.downloadWhisper(modelId: model.id) },
                                        onCancel: { manager.cancelWhisperDownload(modelId: model.id) }
                                    )
                                } else {
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
                                        state: state,
                                        progressText: manager.activeWhisperDownloadText,
                                        isActive: manager.selectedWhisperModelId == model.id && transcriptionManager.currentEngineType == .whisper,
                                        isExpandable: true,
                                        onSetActive: {
                                            manager.selectedWhisperModelId = model.id
                                            transcriptionManager.setEngineType(.whisper)
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
                
                Divider().padding(.vertical, 8)
                
                // LLM Models Section
                VStack(alignment: .leading, spacing: 16) {
                    Text(t("LLM Models"))
                        .font(.system(size: 18, weight: .semibold))
                    
                    ModelCard(
                        title: "Gemma (Text Correction)",
                        description: t("Required for advanced text rewriting and smart corrections. Approx. 3 GB."),
                        state: manager.gemmaState,
                        progressText: manager.activeGemmaDownloadText,
                        onDownload: { manager.downloadGemma() },
                        onPause: { manager.pauseGemmaDownload() },
                        onCancel: { manager.cancelGemmaDownload() },
                        onUninstall: {
                            self.modelToUninstall = .gemma
                            self.showUninstallConfirmation = true
                        }
                    )
                }
                

            }
            .padding(.bottom, 20)
        }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color.clear
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
                                    // Remove MLX model directory
                                    let repo = Hub.Repo(id: manager.availableMLXModels.first(where: { $0.id == id })!.repoId)
                                    let api = HubApi(downloadBase: manager.modelsDirectory, cache: nil, useBackgroundSession: false)
                                    let dir = api.localRepoLocation(repo)
                                    try? FileManager.default.removeItem(at: dir)
                                    manager.mlxStates[id] = .notDownloaded
                                case .gemma:
                                    manager.uninstallGemma()
                                }
                            }
                        },
                        secondaryButton: .cancel(Text(t("Cancel")))
                    )
                }
        )
    }
}
