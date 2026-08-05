import SwiftUI
import Hub

struct CustomDisclosureGroup<Content: View>: View {
    let title: String
    var description: String? = nil
    var modelsCount: Int? = nil
    @State private var isExpanded: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        
                        if let desc = description {
                            Text(t(desc))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 16)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    
                    VStack(spacing: 12) {
                        content()
                    }
                    .padding(16)
                }
                .background(colorScheme == .dark ? Color.white.opacity(0.01) : Color.black.opacity(0.005))
            }
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

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

struct ModelCard: View {
    let title: String
    let description: String
    let state: DownloadState
    var progressText: String? = nil
    var isActive: Bool? = nil
    var onSetActive: (() -> Void)? = nil
    let onDownload: () -> Void
    var onPause: (() -> Void)? = nil
    let onCancel: () -> Void
    var onUninstall: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t(title))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t(description))
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
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 12) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(colorScheme == .dark ? .white : .black)
                                .frame(width: 100)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
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
                        if let pt = progressText {
                            Text(pt)
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                case .paused(let progress):
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 12) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(.secondary)
                                .frame(width: 100)
                                .opacity(0.6)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
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
                        if let pt = progressText {
                            Text(pt)
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                case .downloaded:
                    HStack(spacing: 12) {
                        if let isActive = isActive, let onSetActive = onSetActive {
                            if isActive {
                                Text(t("Active"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(colorScheme == .dark ? Color.white : Color.black)
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
                        if let onUninstall = onUninstall {
                            if title != "Apple Speech (System)" {
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

struct LanguageListView: View {
    let languages: [String]
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isSearchFocused: Bool
    
    var filteredLanguages: [String] {
        if searchText.isEmpty {
            return languages
        }
        return languages.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(t("Supported Languages"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding()
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(t("Search language..."), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
            }
            .padding(10)
            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            Divider()
            
            // List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLanguages, id: \.self) { language in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(language)
                                .font(.system(size: 14))
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            Divider().padding(.leading, 16)
                        }
                    }
                    if filteredLanguages.isEmpty {
                        Text(t("No languages found."))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            isSearchFocused = true
        }
    }
}

struct RichModelCard: View {
    let title: String
    let description: String
    let weight: String
    let languages: String
    let accuracy: Double
    let speed: Double
    let company: String
    let parameters: String?
    let supportedLanguagesList: [String]
    let state: DownloadState
    var progressText: String? = nil
    var isActive: Bool? = nil
    var isExpandable: Bool = false
    var onSetActive: (() -> Void)? = nil
    let onDownload: () -> Void
    var onPause: (() -> Void)? = nil
    let onCancel: () -> Void
    var onUninstall: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded: Bool = false
    @State private var showLanguageList: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top Row: Title, Weight & Actions
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(t(description))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                
                // Action Buttons
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
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 12) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(colorScheme == .dark ? .white : .black)
                                .frame(width: 100)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                            if let onPause = onPause {
                                Button(action: onPause) {
                                    Image(systemName: "pause.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
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
                        if let pt = progressText {
                            Text(pt)
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                case .paused(let progress):
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 12) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(.secondary)
                                .frame(width: 100)
                                .opacity(0.6)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
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
                        if let pt = progressText {
                            Text(pt)
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                case .downloaded:
                    HStack(spacing: 12) {
                        if let isActive = isActive, let onSetActive = onSetActive {
                            if isActive {
                                Text(t("Active"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(colorScheme == .dark ? Color.white : Color.black)
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
                        if let onUninstall = onUninstall {
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
            .contentShape(Rectangle())
            .onTapGesture {
                if isExpandable {
                    if let act = isActive, act == true, isExpanded == true {
                        return // Do not collapse if active
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }
            }
            
            if !isExpandable || isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Metadata Tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "shippingbox")
                                    .foregroundColor(.secondary)
                                Text(t("Weight") + ": " + weight)
                                    .foregroundColor(.secondary)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(4)
                            
                            Button(action: {
                                showLanguageList = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                        .foregroundColor(.secondary)
                                    Text(t("Languages") + ": " + t(languages))
                                        .foregroundColor(.secondary)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "building.2")
                                    .foregroundColor(.secondary)
                                Text(t(company))
                                    .foregroundColor(.secondary)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(4)
                            
                            if let params = parameters {
                                HStack(spacing: 4) {
                                    Image(systemName: "cpu")
                                        .foregroundColor(.secondary)
                                    Text(t(params))
                                        .foregroundColor(.secondary)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                .cornerRadius(4)
                            }
                        }
                    }
                    
                    // Progress Bars
                    VStack(spacing: 8) {
                        HStack {
                            Text(t("Accuracy"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            ProgressView(value: accuracy)
                                .progressViewStyle(.linear)
                                .tint(colorScheme == .dark ? .white : .black)
                        }
                        HStack {
                            Text(t("Speed"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            ProgressView(value: speed)
                                .progressViewStyle(.linear)
                                .tint(colorScheme == .dark ? .white : .black)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(isExpanded || !isExpandable ? 0.04 : 0.02) : Color.black.opacity(isExpanded || !isExpandable ? 0.02 : 0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: isActive) { _, newValue in
            if isExpandable, let act = newValue, act == true {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded = true
                }
            }
        }
        .onAppear {
            if isExpandable, let act = isActive, act == true {
                isExpanded = true
            }
        }
        .sheet(isPresented: $showLanguageList) {
            LanguageListView(languages: supportedLanguagesList)
        }
    }
}

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


struct ActiveDownloadCard: View {
    let title: String
    let descriptionText: String
    let state: DownloadState
    let stats: ModelManager.DownloadStats?
    
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    Text(t(descriptionText))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                
                if isExpanded {
                    // Status Tag
                    HStack(spacing: 4) {
                        if state.isDownloading {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(t("Downloading"))
                        } else if state.isPaused {
                            Image(systemName: "pause.circle.fill")
                            Text(t("Paused"))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(state.isDownloading ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            
            Divider().padding(.vertical, -4)
            
            if isExpanded {
                // Stats Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        let progressPct = (stats?.totalBytes ?? 0) > 0 ? Double(stats?.downloadedBytes ?? 0) / Double(stats?.totalBytes ?? 1) : 0
                        Text(String(format: "%.1f%%", progressPct * 100))
                            .font(.system(size: 24, weight: .bold).monospacedDigit())
                        
                        if let stats = stats, stats.totalBytes > 0 {
                            Text("\(formatBytes(stats.downloadedBytes)) / \(formatBytes(stats.totalBytes))")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        if let stats = stats {
                            let speedStr = formatBytes(Int64(stats.speedBytesPerSecond))
                            Text("\(speedStr)/s")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundColor(state.isDownloading ? .primary : .secondary)
                                
                            let remainingBytes = stats.totalBytes - stats.downloadedBytes
                            if remainingBytes > 0 && stats.speedBytesPerSecond > 0 {
                                let recentSpeeds = stats.speedHistory.suffix(10)
                                let avgSpeed = recentSpeeds.isEmpty ? stats.speedBytesPerSecond : (recentSpeeds.reduce(0, +) / Double(recentSpeeds.count))
                                let effectiveSpeed = avgSpeed > 0 ? avgSpeed : stats.speedBytesPerSecond
                                let secondsRemaining = Double(remainingBytes) / effectiveSpeed
                                Text("\(t("Time left:")) \(formatTime(seconds: secondsRemaining))")
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundColor(.secondary)
                            } else {
                                Text(t("Current Speed"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("0 KB/s")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundColor(.secondary)
                            Text(t("Current Speed"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Chart Area
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
                        .frame(height: 60)
                    
                    if let stats = stats, !stats.speedHistory.isEmpty {
                        DownloadSpeedChart(history: stats.speedHistory)
                            .frame(height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            
            // Controls & Progress
            HStack(spacing: 12) {
                // Play/Pause
                Button(action: {
                    if state.isDownloading {
                        onPause()
                    } else if case .paused = state {
                        onResume()
                    }
                }) {
                    Image(systemName: state.isDownloading ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(width: 32, height: 32)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                let progressPct = (stats?.totalBytes ?? 0) > 0 ? Double(stats?.downloadedBytes ?? 0) / Double(stats?.totalBytes ?? 1) : 0
                
                if !isExpanded {
                    Text(String(format: "%.0f%%", progressPct * 100))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(state.isDownloading ? (colorScheme == .dark ? Color.white : Color.black) : Color.secondary)
                            .frame(width: max(0, geo.size.width * CGFloat(progressPct)), height: 8)
                    }
                }
                .frame(height: 8)
                
                // Cancel Button
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatTime(seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds > 31536000 || seconds < -31536000 { return "--:--" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

struct DownloadSpeedChart: View {
    let history: [Double]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geo in
            let maxSpeed = history.max() ?? 1.0
            let effectiveMax = maxSpeed == 0 ? 1.0 : maxSpeed
            let width = geo.size.width
            let height = geo.size.height
            let safeWidth = (width.isNaN || width.isInfinite) ? 100 : width
            let safeHeight = (height.isNaN || height.isInfinite) ? 10 : height
            
            let barCount = 60
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(max(0, barCount - 1))
            let barWidth = max(1, (safeWidth - totalSpacing) / CGFloat(barCount))
            
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(history.enumerated()), id: \.offset) { index, speed in
                    let rawHeight = CGFloat(speed / effectiveMax) * safeHeight
                    let safeRawHeight = (rawHeight.isNaN || rawHeight.isInfinite) ? 0 : rawHeight
                    let barHeight = max(2, safeRawHeight)
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .frame(width: barWidth, height: barHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
