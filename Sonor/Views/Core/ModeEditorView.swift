import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ScreenCaptureKit

struct ModeEditorView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var modes: [VoiceMode]
    @Binding var selectedModeID: String
    
    @State private var showDeleteConfirmation = false
    @State private var showActiveModeDeleteAlert = false
    @State private var showConflictAlert = false
    @State private var conflictingBundleID: String? = nil
    @State private var assistantWithConflictingApp: VoiceMode? = nil
    @State private var showAssistantTypeInfo = false
    @State private var showRenameSheet = false
    @State private var newAssistantName = ""
    @ObservedObject private var modelManager = ModelManager.shared
    
    var downloadedModels: [(id: String, name: String)] {
        var list: [(id: String, name: String)] = []
        list.append((id: "appleSpeech", name: t("Apple Speech (System)")))
        for model in modelManager.availableWhisperModels {
            if modelManager.whisperStates[model.id] == .downloaded {
                list.append((id: model.id, name: model.name))
            }
        }
        for model in modelManager.availableMLXModels {
            if modelManager.mlxStates[model.id] == .downloaded {
                list.append((id: model.id, name: model.name))
            }
        }
        return list
    }
    
    var body: some View {
        if let index = modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) {
            let modeBinding = Binding<VoiceMode>(
                get: { modes[index] },
                set: { 
                    modes[index] = $0
                    saveModes()
                }
            )
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    if modeBinding.wrappedValue.isBuiltInMode {
                        Text(t(modeBinding.wrappedValue.name))
                            .font(.system(size: 18, weight: .bold))
                    } else {
                        Text(modeBinding.wrappedValue.name)
                            .font(.system(size: 18, weight: .bold))
                    }
                    Spacer()
                }
                .alert(isPresented: $showDeleteConfirmation) {
                    Alert(
                        title: Text(t("Delete Assistant")),
                        message: Text(t("Are you sure you want to delete this assistant? This operation cannot be undone.")),
                        primaryButton: .destructive(Text(t("Delete"))) {
                            deleteCurrentMode()
                        },
                        secondaryButton: .cancel(Text(t("Cancel")))
                    )
                }
                
                Divider()
                    .alert(isPresented: $showConflictAlert) {
                        Alert(
                            title: Text(t("App Already Assigned")),
                            message: Text(String(format: t("This application is already used in the assistant '%@'. Do you want to move it to this assistant?"), assistantWithConflictingApp?.name ?? "")),
                            primaryButton: .destructive(Text(t("Move"))) {
                                resolveConflict()
                            },
                            secondaryButton: .cancel(Text(t("Cancel")))
                        )
                    }
                
                editorScrollView(modeBinding: modeBinding)
                    .padding(.trailing, 10) 
                    .alert(isPresented: $showActiveModeDeleteAlert) {
                        Alert(
                            title: Text(t("Cannot Delete")),
                            message: Text(t("You cannot delete the assistant that is currently being used for speaking.")),
                            dismissButton: .default(Text(t("OK")))
                        )
                    }
                }
                .padding(20)
                .frame(width: 300)
                .safeGlassEffect(cornerRadius: NSWindow.standardCornerRadius)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
                .padding(.top, 8)
                .ignoresSafeArea(edges: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .sheet(isPresented: $showAssistantTypeInfo) {
                    AssistantTypeExplanationView()
                        .preferredColorScheme(colorScheme)
                }

        }
    }
    
    
    private var renameSheetContent: some View {
        let otherModes = modes.filter { $0.id.uuidString != selectedModeID }
        let nameExists = otherModes.contains(where: { $0.name.lowercased() == newAssistantName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let isNameEmpty = newAssistantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return VStack(alignment: .leading, spacing: 16) {
            Text(t("Rename Assistant"))
                .font(.headline)
            
            TextField(t("Enter new name for the assistant:"), text: $newAssistantName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: newAssistantName) { _, newValue in
                    if newValue.count > 50 {
                        newAssistantName = String(newValue.prefix(50))
                    }
                }
                .onSubmit {
                    let finalName = newAssistantName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalName.isEmpty && !nameExists {
                        if let idx = modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) {
                            modes[idx].name = finalName
                            saveModes()
                        }
                        showRenameSheet = false
                    }
                }
            
            if nameExists {
                Text(t("Name already exists."))
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            HStack {
                Spacer()
                Button(t("Cancel")) {
                    showRenameSheet = false
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(8)
                
                Button(t("Save")) {
                    let finalName = newAssistantName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalName.isEmpty && !nameExists {
                        if let idx = modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) {
                            modes[idx].name = finalName
                            saveModes()
                        }
                        showRenameSheet = false
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(nameExists || isNameEmpty ? Color.primary.opacity(0.3) : (colorScheme == .dark ? Color.white : Color.black))
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .cornerRadius(8)
                .disabled(nameExists || isNameEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(colorScheme == .dark ? Color(white: 0.1) : Color.white)
        .preferredColorScheme(colorScheme)
    }
    
    
    private func saveModes() {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: "voiceModes")
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
        }
    }



    private func selectApplication() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [UTType.application]
            if panel.runModal() == .OK, let url = panel.url {
                let bundle = Bundle(url: url)
                var detectedBundleID = bundle?.bundleIdentifier
                if detectedBundleID == nil {
                    let plistURL = url.appendingPathComponent("Contents/Info.plist")
                    if let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
                       let id = dict["CFBundleIdentifier"] as? String {
                        detectedBundleID = id
                    }
                }
                let bundleID = detectedBundleID ?? url.lastPathComponent
                if let existingAssistant = self.findAssistantWithApp(bundleID: bundleID) {
                    self.assistantWithConflictingApp = existingAssistant
                    self.conflictingBundleID = bundleID
                    self.showConflictAlert = true
                } else {
                    self.addAppToCurrentMode(bundleID)
                }
            }
        }
    }
    private func findAssistantWithApp(bundleID: String) -> VoiceMode? {
        return modes.first(where: { $0.id.uuidString != selectedModeID && $0.boundAppBundleIDs.contains(bundleID) })
    }
    private func addAppToCurrentMode(_ bundleID: String) {
        if let index = modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) {
            if !modes[index].boundAppBundleIDs.contains(bundleID) {
                modes[index].boundAppBundleIDs.append(bundleID)
                saveModes()
            }
        }
    }
    func resolveConflict() {
        guard let conflictID = conflictingBundleID, let existingAss = assistantWithConflictingApp else { return }
        if let index = modes.firstIndex(where: { $0.id == existingAss.id }) {
            modes[index].boundAppBundleIDs.removeAll(where: { $0 == conflictID })
        }
        if let index = modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) {
            if !modes[index].boundAppBundleIDs.contains(conflictID) {
                modes[index].boundAppBundleIDs.append(conflictID)
            }
        }
        saveModes()
        showConflictAlert = false
    }
    private func removeApp(_ bundleID: String) {
        if let index = modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) {
            modes[index].boundAppBundleIDs.removeAll(where: { $0 == bundleID })
            saveModes()
        }
    }
    private func getAppIcon(bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
    private func deleteCurrentMode() {
        let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
        let isDeletingActive = selectedModeID == activeModeID
        modes.removeAll(where: { $0.id.uuidString == selectedModeID })
        saveModes()
        selectedModeID = modes.first?.id.uuidString ?? ""
        if isDeletingActive {
            UserDefaults.standard.set(selectedModeID, forKey: "activeModeID")
            NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
        }
    }

    @ViewBuilder
    private func editorScrollView(modeBinding: Binding<VoiceMode>) -> some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !modeBinding.wrappedValue.isBuiltInMode {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text(t("Assistant Type"))
                                        .font(.system(size: 14, weight: .semibold))
                                    Button(action: {
                                        showAssistantTypeInfo = true
                                    }) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 4)
                                HStack(spacing: 0) {
                                    Button(action: {
                                        modeBinding.wrappedValue.assistantType = "dictation"
                                    }) {
                                        Text(t("Dictation & Correction"))
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity)
                                            .background(modeBinding.wrappedValue.assistantType == "dictation" ? (colorScheme == .dark ? .white : .black) : Color.clear)
                                            .foregroundColor(modeBinding.wrappedValue.assistantType == "dictation" ? (colorScheme == .dark ? .black : .white) : .secondary)
                                            .cornerRadius(6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                        .frame(height: 15)
                                    Button(action: {
                                        modeBinding.wrappedValue.assistantType = "edit"
                                    }) {
                                        Text(t("Editing & Creation"))
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity)
                                            .background(modeBinding.wrappedValue.assistantType == "edit" ? (colorScheme == .dark ? .white : .black) : Color.clear)
                                            .foregroundColor(modeBinding.wrappedValue.assistantType == "edit" ? (colorScheme == .dark ? .black : .white) : .secondary)
                                            .cornerRadius(6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(2)
                                .safeGlassEffect(cornerRadius: 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear)
                                )
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            }
                        }
                        if modeBinding.wrappedValue.assistantType == "edit" {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(t("Pass application name"), isOn: Binding(
                                    get: { modeBinding.wrappedValue.passAppName ?? false },
                                    set: { modeBinding.wrappedValue.passAppName = $0 }
                                ))
                                .toggleStyle(CustomToggleStyle())
                                .font(.system(size: 12))
                                Toggle(t("Pass copied text"), isOn: Binding(
                                    get: { modeBinding.wrappedValue.passCopiedText ?? false },
                                    set: { modeBinding.wrappedValue.passCopiedText = $0 }
                                ))
                                .toggleStyle(CustomToggleStyle())
                                .font(.system(size: 12))
                            }
                        }

                        if modeBinding.wrappedValue.name != "Pure Text" {
                            HStack {
                                Text(t("Language"))
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { modeBinding.wrappedValue.language ?? "auto" },
                                    set: { modeBinding.wrappedValue.language = $0 }
                                )) {
                                    Text(t("Automatic")).tag("auto")
                                    Text(t("العربية")).tag("ar")
                                    Text(t("中文")).tag("zh")
                                    Text(t("Čeština")).tag("cs")
                                    Text(t("Dansk")).tag("da")
                                    Text(t("Nederlands")).tag("nl")
                                    Text(t("English")).tag("en")
                                    Text(t("Suomi")).tag("fi")
                                    Text(t("Français")).tag("fr")
                                    Text(t("Deutsch")).tag("de")
                                    Text(t("Ελληνικά")).tag("el")
                                    Text(t("עברית")).tag("he")
                                    Text(t("हिन्दी")).tag("hi")
                                    Text(t("Magyar")).tag("hu")
                                    Text(t("Italiano")).tag("it")
                                    Text(t("日本語")).tag("ja")
                                    Text(t("한국어")).tag("ko")
                                    Text(t("Norsk")).tag("no")
                                    Text(t("Polski")).tag("pl")
                                    Text(t("Português")).tag("pt")
                                    Text(t("Português (Brasil)")).tag("pt-BR")
                                    Text(t("Română")).tag("ro")
                                    Text(t("Русский")).tag("ru")
                                    Text(t("Slovenčina")).tag("sk")
                                    Text(t("Español")).tag("es")
                                    Text(t("Svenska")).tag("sv")
                                    Text(t("ไทย")).tag("th")
                                    Text(t("Türkçe")).tag("tr")
                                    Text(t("Українська")).tag("uk")
                                    Text(t("Tiếng Việt")).tag("vi")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 150)
                            }
                        }
                        
                        HStack {
                            Text(t("Model"))
                                .font(.system(size: 12))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { modeBinding.wrappedValue.modelOverride ?? "default" },
                                set: { 
                                    let newVal = $0 == "default" ? nil : $0
                                    modeBinding.wrappedValue.modelOverride = newVal
                                    saveModes()
                                    TranscriptionManager.shared.applyModelOverride(newVal)
                                    if modeBinding.wrappedValue.id.uuidString == UserDefaults.standard.string(forKey: "activeModeID") {
                                        Task {
                                            try? await TranscriptionManager.shared.ensureEngineReady()
                                        }
                                    }
                                }
                            )) {
                                Text(t("Default")).tag("default")
                                ForEach(downloadedModels, id: \.id) { m in
                                    Text(m.name).tag(m.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if modeBinding.wrappedValue.isBuiltInMode {
                                Text(t("Built-in Assistant Description"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 4)
                                let description: String = {
                                    switch modeBinding.wrappedValue.name {
                                    case "Pure Text":
                                        return t("Performs pure 1:1 transcription of your speech, without any corrections or AI editing.")
                                    case "Text Smoothing":
                                        return t("Removes stutters, repetitions, and grammatical errors and inserts appropriate punctuation. Preserves the original style, tone, and vocabulary of your statement.")
                                    case "Formal Style":
                                        return t("Automatically transforms loose thoughts into professional, elegant, and official style. Ideal for formal communication.")
                                    case "Casual Style":
                                        return t("Transforms text into a casual, relaxed, and conversational style with natural colloquialisms. Ideal for friendly communication.")
                                    case "Edit & Create":
                                        return t("Acts as an expert editor. It perfectly executes your spoken instructions to edit, rewrite, or generate brand new texts. Ideal for creating custom content on the fly.")
                                    default:
                                        return t("Built-in system assistant.")
                                    }
                                }()
                                Text(description)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .safeGlassEffect(cornerRadius: 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.clear)
                                    )
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 8)
                            } else {
                                Text(t("AI Prompt"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 4)
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: modeBinding.prompt)
                                        .font(.system(size: 13))
                                        .frame(height: 80)
                                        .padding(4)
                                        .scrollContentBackground(.hidden)
                                        .safeGlassEffect(cornerRadius: 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear)
                                        )
                                        .onChange(of: modeBinding.wrappedValue.prompt) { _, newValue in
                                            if newValue.count > 10000 {
                                                modeBinding.wrappedValue.prompt = String(newValue.prefix(10000))
                                            }
                                        }
                                    if modeBinding.wrappedValue.prompt.isEmpty {
                                        Text(t("Enter your prompt here..."))
                                            .font(.system(size: 13))
                                            .foregroundColor(Color.secondary.opacity(0.5))
                                            .padding(.leading, 10)
                                            .padding(.top, 4)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(t("App Automation"))
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button(action: {
                                    selectApplication()
                                }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(4)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
                                }
                                .buttonStyle(.plain)
                            }
                            if !modeBinding.wrappedValue.boundAppBundleIDs.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(modeBinding.wrappedValue.boundAppBundleIDs, id: \.self) { bundleID in
                                            ZStack(alignment: .topTrailing) {
                                                if let icon = getAppIcon(bundleID: bundleID) {
                                                    Image(nsImage: icon)
                                                        .resizable()
                                                        .frame(width: 48, height: 48)
                                                        .cornerRadius(6)
                                                } else {
                                                    Image(systemName: "app.dashed")
                                                        .resizable()
                                                        .frame(width: 48, height: 48)
                                                        .foregroundColor(.secondary)
                                                        .background(Color.primary.opacity(0.05))
                                                        .cornerRadius(6)
                                                }
                                                Button(action: {
                                                    removeApp(bundleID)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 16))
                                                        .foregroundColor(.secondary)
                                                        .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                                                }
                                                .buttonStyle(.plain)
                                                .offset(x: 2, y: -2)
                                            }
                                            .frame(width: 48, height: 48)
                                            .padding(.trailing, 5)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                }
                            } else {
                                Text(t("No apps assigned."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Toggle(t("Mute system during recording"), isOn: Binding(
                                get: { 
                                    let b = modeBinding.wrappedValue.audioBehavior ?? .keep
                                    return b == .mute || b == .muteAndPause 
                                },
                                set: { newValue in
                                    let current = modeBinding.wrappedValue.audioBehavior ?? .keep
                                    if newValue {
                                        modeBinding.wrappedValue.audioBehavior = (current == .pause || current == .muteAndPause) ? .muteAndPause : .mute
                                    } else {
                                        modeBinding.wrappedValue.audioBehavior = (current == .muteAndPause) ? .pause : .keep
                                    }
                                    saveModes()
                                }
                            ))
                            .toggleStyle(CustomToggleStyle())
                            .font(.system(size: 12))
                            Button(action: {
                                let newVal = modeBinding.wrappedValue.audioBehavior ?? .keep
                                for i in modes.indices {
                                    modes[i].audioBehavior = newVal
                                }
                                saveModes()
                            }) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(t("Apply to all assistants"))
                        }
                        HStack {
                            Toggle(t("Pause media during recording"), isOn: Binding(
                                get: { 
                                    let b = modeBinding.wrappedValue.audioBehavior ?? .keep
                                    return b == .pause || b == .muteAndPause 
                                },
                                set: { newValue in
                                    let current = modeBinding.wrappedValue.audioBehavior ?? .keep
                                    if newValue {
                                        modeBinding.wrappedValue.audioBehavior = (current == .mute || current == .muteAndPause) ? .muteAndPause : .pause
                                    } else {
                                        modeBinding.wrappedValue.audioBehavior = (current == .muteAndPause) ? .mute : .keep
                                    }
                                    saveModes()
                                }
                            ))
                            .toggleStyle(CustomToggleStyle())
                            .font(.system(size: 12))
                            Button(action: {
                                let newVal = modeBinding.wrappedValue.audioBehavior ?? .keep
                                for i in modes.indices {
                                    modes[i].audioBehavior = newVal
                                }
                                saveModes()
                            }) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(t("Apply to all assistants"))
                        }

                        HStack {
                            Picker(t("Post-paste action"), selection: Binding(
                                get: { modeBinding.wrappedValue.postPasteAction ?? "none" },
                                set: { 
                                    modeBinding.wrappedValue.postPasteAction = $0
                                    saveModes()
                                }
                            )) {
                                Text(t("None")).tag("none")
                                Text(t("Return")).tag("return")
                                Text(t("Shift + Return")).tag("shiftReturn")
                                Text(t("Command + Return")).tag("commandReturn")
                                Text(t("Option + Return")).tag("optionReturn")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .font(.system(size: 12))
                            
                            Button(action: {
                                let newVal = modeBinding.wrappedValue.postPasteAction ?? "none"
                                for i in modes.indices {
                                    modes[i].postPasteAction = newVal
                                }
                                saveModes()
                            }) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(t("Apply to all assistants"))
                        }

                        HStack {
                            Picker(t("Behavior if no field detected"), selection: Binding(
                                get: { modeBinding.wrappedValue.fallbackBehavior ?? "overlay" },
                                set: { 
                                    modeBinding.wrappedValue.fallbackBehavior = $0
                                    saveModes()
                                }
                            )) {
                                Text(t("Do nothing")).tag("none")
                                Text(t("Show overlay")).tag("overlay")
                                Text(t("Copy to clipboard")).tag("clipboard")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .font(.system(size: 12))
                            
                            Button(action: {
                                let newVal = modeBinding.wrappedValue.fallbackBehavior ?? "overlay"
                                for i in modes.indices {
                                    modes[i].fallbackBehavior = newVal
                                }
                                saveModes()
                            }) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(t("Apply to all assistants"))
                        }

                    }
                    Spacer()
                    Divider()
                    if !modeBinding.wrappedValue.isBuiltInMode {
                        Button(action: {
                            newAssistantName = modeBinding.wrappedValue.name
                            showRenameSheet = true
                        }) {
                            HStack {
                                Image(systemName: "pencil")
                                Text(t("Rename Assistant"))
                            }
                            .foregroundColor(.primary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showRenameSheet) {
                            renameSheetContent
                        }
                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text(t("Delete Assistant"))
                            }
                            .foregroundColor(.red)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
    }
}
