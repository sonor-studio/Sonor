import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var manager = ModelManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showUninstallConfirmation = false
    @State private var modelToUninstall: ModelType? = nil
    enum ModelType {
        case whisper(id: String)
        case gemma
    }
    var body: some View {
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
                        Button(action: { manager.showWhisperModelSelector = true }) {
                            Text(t("Add Model"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    let activeOrDownloadingWhisperModels = manager.availableWhisperModels.filter { model in
                        guard let state = manager.whisperStates[model.id] else { return false }
                        switch state {
                        case .notDownloaded: return false
                        default: return true
                        }
                    }
                    
                    if activeOrDownloadingWhisperModels.isEmpty {
                        Text(t("No transcription models downloaded. Click 'Add Model' to download one."))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(activeOrDownloadingWhisperModels) { model in
                            ModelCard(
                                title: model.name,
                                description: model.description,
                                state: manager.whisperStates[model.id] ?? .notDownloaded,
                                isActive: manager.selectedWhisperModelId == model.id,
                                onSetActive: {
                                    manager.selectedWhisperModelId = model.id
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
                
                Divider().padding(.vertical, 8)
                
                // LLM Models Section
                VStack(alignment: .leading, spacing: 16) {
                    Text(t("LLM Models"))
                        .font(.system(size: 18, weight: .semibold))
                    
                    ModelCard(
                        title: "Gemma (Text Correction)",
                        description: t("Required for advanced text rewriting and smart corrections. Approx. 3 GB."),
                        state: manager.gemmaState,
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

struct ModelCard: View {
    let title: String
    let description: String
    let state: DownloadState
    var isActive: Bool? = nil
    var onSetActive: (() -> Void)? = nil
    let onDownload: () -> Void
    var onPause: (() -> Void)? = nil
    let onCancel: () -> Void
    let onUninstall: () -> Void
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                switch state {
                case .notDownloaded:
                        Button(action: onDownload) {
                            Text(t("Download"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(colorScheme == .dark ? Color.white : Color.black)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                case .downloading(let progress):
                    HStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(colorScheme == .dark ? .white : .black)
                            .frame(width: 100)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                        if let onPause = onPause {
                            Button(action: onPause) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                case .paused(let progress):
                    HStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.secondary)
                            .frame(width: 100)
                            .opacity(0.6)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                        Button(action: onDownload) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .buttonStyle(.plain)
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                case .downloaded:
                    HStack(spacing: 12) {
                        if let isActive = isActive, let onSetActive = onSetActive {
                            if isActive {
                                Text(t("Active"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(6)
                            } else {
                                Button(action: onSetActive) {
                                    Text(t("Set Active"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button(action: onUninstall) {
                            Text(t("Uninstall"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

struct WhisperModelSelectorView: View {
    @ObservedObject var manager = ModelManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showUninstallConfirmation = false
    @State private var modelToUninstall: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(t("Select Transcription Model"))
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: { manager.showWhisperModelSelector = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(manager.availableWhisperModels) { model in
                        ModelCard(
                            title: model.name,
                            description: model.description,
                            state: manager.whisperStates[model.id] ?? .notDownloaded,
                            isActive: manager.selectedWhisperModelId == model.id,
                            onSetActive: {
                                manager.selectedWhisperModelId = model.id
                                manager.showWhisperModelSelector = false
                            },
                            onDownload: { manager.downloadWhisper(modelId: model.id) },
                            onPause: { manager.pauseWhisperDownload(modelId: model.id) },
                            onCancel: { manager.cancelWhisperDownload(modelId: model.id) },
                            onUninstall: {
                                self.modelToUninstall = model.id
                                self.showUninstallConfirmation = true
                            }
                        )
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
        .preferredColorScheme(colorScheme)
        .alert(isPresented: $showUninstallConfirmation) {
            Alert(
                title: Text(t("Uninstall Model")),
                message: Text(t("Are you sure you want to uninstall this model?")),
                primaryButton: .destructive(Text(t("Uninstall"))) {
                    if let id = modelToUninstall {
                        manager.uninstallWhisper(modelId: id)
                    }
                },
                secondaryButton: .cancel(Text(t("Cancel")))
            )
        }
    }
}
