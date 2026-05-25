import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon
import Charts

enum ProcessingMode: String, CaseIterable, Identifiable {
    case raw = "Dyktowanie"
    case cleanup = "Poprawianie"
    case formal = "Formalny"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .raw: return "Wkleja tekst dokładnie tak, jak usłyszał go Sonor, bez użycia modelu LLM."
        case .cleanup: return "Układa wypowiedź ładnie i schludnie. Dodaje interpunkcję, poprawia błędy i luki. Zachowuje oryginalny sens, styl i proporcje."
        case .formal: return "Zmienia styl wypowiedzi na formalny. Nie zmienia znaczenia i nie dodaje nowego sensu ani nie usuwa treści."
        }
    }
}

enum SettingsTab: String {
    case home = "Dom"
    case modes = "Asystenci"
    case dictionary = "Słownik"
    case snippets = "Snippety"
    case models = "Modele"
    case settings = "Ustawienia"
}

enum HotkeyMode: String, CaseIterable, Identifiable {
    case click = "Click"
    case hold = "Hold"
    var id: String { self.rawValue }
}

struct SettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var localizer = LocalizationManager.shared
    @State private var selectedTab: SettingsTab = .home
    @AppStorage("processingMode") private var processingMode: ProcessingMode = .raw
    @AppStorage("appTheme") private var appTheme = "system"
    
    var effectiveColorScheme: ColorScheme {
        if appTheme == "dark" {
            return .dark
        } else if appTheme == "light" {
            return .light
        } else {
            let appleInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            return appleInterfaceStyle == "Dark" ? .dark : .light
        }
    }
    
    @State private var modes: [VoiceMode] = []
    @AppStorage("selectedModeID") private var selectedModeID: String = ""
    @State private var isShowingSidePanel = false
    
    // State for app conflict alert
    @State private var showConflictAlert = false
    @State private var conflictingBundleID: String? = nil
    @State private var assistantWithConflictingApp: VoiceMode? = nil
    @State private var showDeleteConfirmation = false
    @State private var showActiveModeDeleteAlert = false
    @State private var isHoveringTrafficLights = false
    @FocusState private var isDummyFocused: Bool
    
    @ObservedObject private var authManager = AuthManager.shared
    @State private var showLoginSheet = false
    @State private var isShowingProfileSheet = false
    @State private var isProfileCardHovered = false
    
    @ObservedObject private var modelManager = ModelManager.shared
    
    var body: some View {
        NavigationSplitView {
            // Panel boczny (Sidebar)
            VStack(alignment: .leading, spacing: 0) {
                // Górne opcje
                VStack(spacing: 5) {
                    MenuButton(title: t("Home"), icon: "house.fill", isSelected: selectedTab == .home) {
                        selectedTab = .home
                    }
                    MenuButton(title: t("Assistants"), icon: "square.grid.2x2.fill", isSelected: selectedTab == .modes) {
                        selectedTab = .modes
                    }
                    MenuButton(title: t("Dictionary"), icon: "book.closed.fill", isSelected: selectedTab == .dictionary) {
                        selectedTab = .dictionary
                    }
                    MenuButton(title: t("Snippets"), icon: "scissors", isSelected: selectedTab == .snippets) {
                        selectedTab = .snippets
                    }
                }
                .padding(.horizontal, 10)
                
                Spacer() // Pcha dolną sekcję na dół
                
                MenuButton(title: t("Models"), icon: "shippingbox.fill", isSelected: selectedTab == .models) {
                    selectedTab = .models
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 5)
                
                // Dolna sekcja (Użytkownik i Ustawienia)
                VStack(spacing: 15) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Panel użytkownika
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(authManager.isLoggedIn ? .primary : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authManager.isLoggedIn ? t("Premium") : t("User"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(authManager.currentUserEmail ?? t("Free account"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(authManager.isLoggedIn && isProfileCardHovered ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if authManager.isLoggedIn {
                            isShowingProfileSheet = true
                        }
                    }
                    .onHover { hovering in
                        if authManager.isLoggedIn {
                            isProfileCardHovered = hovering
                        }
                    }
                    .padding(.horizontal, -3) // Adjust layout since padding was increased from 5 to 8
                    
                    if authManager.isLoggedIn {
                        Button(action: {
                            authManager.logout()
                        }) {
                            Text(t("Log Out"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 5)
                    } else {
                        Button(action: {
                            showLoginSheet = true
                        }) {
                            Text(t("Log In"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(colorScheme == .dark ? Color.white : Color.black)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 5)
                    }
                    
                    // Przycisk ustawień
                    MenuButton(title: t("Settings"), icon: "gearshape.fill", isSelected: selectedTab == .settings) {
                        selectedTab = .settings
                    }
                }
                .padding(.bottom, 20)
                .padding(.leading, 10)
                .padding(.trailing, 30)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            // Główny panel treści (po prawej)
            HStack(spacing: 0) {
                // Ukryty element przejmujący fokus, aby pasek boczny nie był domyślnie zaznaczony
                TextField("", text: .constant(""))
                    .textFieldStyle(.plain)
                    .frame(width: 0, height: 0)
                    .focused($isDummyFocused)
                    .offset(x: -1000, y: -1000)
                
                if !authManager.isLoggedIn && (selectedTab == .dictionary || selectedTab == .snippets) {
                    PremiumLockView(showLoginSheet: $showLoginSheet)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch selectedTab {
                            case .home:
                                StatisticsView()
                            case .modes:
                                ModesSettingsView(modes: $modes, selectedModeID: $selectedModeID, isShowingSidePanel: $isShowingSidePanel, isPremium: authManager.isLoggedIn, showLoginSheet: $showLoginSheet)
                            case .dictionary:
                                DictionarySettingsView()
                            case .snippets:
                                SnippetsSettingsView()
                            case .models:
                                ModelsSettingsView()
                            case .settings:
                                HomeSettingsView()
                            }
                            Spacer()
                        }
                        .padding(30)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                
                // Panel boczny (Opcje) widoczny cały czas dla wybranego asystenta
                if selectedTab == .modes && (authManager.isLoggedIn || modes.first(where: { $0.id.uuidString == selectedModeID })?.name == "Raw Output" || modes.first(where: { $0.id.uuidString == selectedModeID })?.name == "Zwykły output"), let index = modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) {
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
                                    TextField("Nazwa asystenta", text: modeBinding.name)
                                        .font(.system(size: 18, weight: .bold))
                                        .textFieldStyle(.plain)
                                }
                                Spacer()
                            }
                            
                            Divider()
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                            if !modeBinding.wrappedValue.isBuiltInMode {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(t("Assistant Type"))
                                        .font(.system(size: 14, weight: .semibold))
                                    
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
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear)
                                    )
                                }
                            }
                            
                            // Opcje kontekstu dla Edycji i Tworzenia
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

                            if modeBinding.wrappedValue.name != "Raw Output" && modeBinding.wrappedValue.name != "Zwykły output" {
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
                                    .accentColor(.black)
                                    .tint(.black)
                                }
                            }
                                
                            // Sekcja 1: Prompt lub Opis dla asystentów wbudowanych
                            VStack(alignment: .leading, spacing: 8) {
                                if modeBinding.wrappedValue.isBuiltInMode {
                                    Text(t("Built-in Assistant Description"))
                                        .font(.system(size: 14, weight: .semibold))
                                    
                                    let description: String = {
                                        switch modeBinding.wrappedValue.name {
                                        case "Raw Output", "Zwykły output":
                                            return t("Performs pure 1:1 transcription of your speech, without any corrections or AI editing.")
                                        case "Text Smoothing", "Wygładzanie tekstu":
                                            return t("Removes stutters, repetitions, and grammatical errors and inserts appropriate punctuation. Preserves the original style, tone, and vocabulary of your statement.")
                                        case "Formal Email", "Formalny e-mail":
                                            return t("Automatically transforms loose thoughts into professional, elegant, and official business correspondence. Ideal for writing emails quickly.")
                                        case "Structured Note", "Ustrukturyzowana notatka":
                                            return t("Reorganizes dictated thoughts into an extremely neat text note. Uses spacing, indents, and traditional lists (e.g. 1., 2. or -).")
                                        default:
                                            return t("Built-in system assistant.")
                                        }
                                    }()
                                    
                                    Text(description)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.clear)
                                        )
                                } else {
                                    Text(t("AI Prompt"))
                                        .font(.system(size: 14, weight: .semibold))
                                    TextEditor(text: modeBinding.prompt)
                                        .frame(height: 80)
                                        .padding(4)
                                        .scrollContentBackground(.hidden)
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear)
                                        )
                                }
                            }
                            
                            // Sekcja 2: Automatyzacja
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
                            
                                                Toggle(t("Pause music"), isOn: modeBinding.pauseMusic)
                                .toggleStyle(CustomToggleStyle())
                                .font(.system(size: 12))
                                

                            }
                            
                            Spacer()
                            
                            Divider()
                            
                            if !modeBinding.wrappedValue.isBuiltInMode {
                                Button(action: {
                                    let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
                                    if modeBinding.wrappedValue.id.uuidString == activeModeID {
                                        showActiveModeDeleteAlert = true
                                    } else {
                                        showDeleteConfirmation = true
                                    }
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
                            }
                                }
                                .padding(.trailing, 10) // Mały odstęp od paska przewijania
                            }
                        .padding(20)
                        .frame(width: 300)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                        .padding(.top, 8)
                        .ignoresSafeArea(edges: .top)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, idealWidth: 1200, minHeight: 600, idealHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(30)
        .ignoresSafeArea()
        .preferredColorScheme(effectiveColorScheme)
        .onAppear {
            isDummyFocused = true
        }
        .alert(isPresented: $showConflictAlert) {
            Alert(
                title: Text(t("App Already Assigned")),
                message: Text("Ta aplikacja jest już używana w asystencie '\(assistantWithConflictingApp?.name ?? "")'. Czy chcesz ją przenieść do tego asystenta?"),
                primaryButton: .destructive(Text(t("Move"))) {
                    resolveConflict()
                },
                secondaryButton: .cancel(Text(t("Cancel")))
            )
        }

        .alert(isPresented: $showActiveModeDeleteAlert) {
            Alert(
                title: Text(t("Cannot Delete")),
                message: Text(t("You cannot delete the assistant that is currently being used for speaking.")),
                dismissButton: .default(Text(t("OK")))
            )
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .frame(width: 400)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { showLoginSheet = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .padding(15)
                        }
                        Spacer()
                    }
                )
        }
        .sheet(isPresented: $isShowingProfileSheet) {
            UserProfileView()
        }
        .background(
            Color.clear
                .sheet(isPresented: $modelManager.showModelsRequiredModal) {
                    ModelsRequiredExplanationView()
                }
                .sheet(isPresented: $modelManager.showDownloadErrorModal) {
                    ModelDownloadErrorView(error: modelManager.downloadError ?? t("An unknown network error occurred."))
                }
        )
        .onAppear {
            loadModes()
        }
    }
    
    private func loadModes() {
        self.modes = VoiceMode.loadAndMigrateModes()
        
        if selectedModeID.isEmpty, let first = modes.first {
            selectedModeID = first.id.uuidString
        }
    }
    
    private func saveModes() {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: "voiceModes")
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
                
                // Sprawdź czy aplikacja jest już w innym asystencie
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
        
        // Usuń z poprzedniego asystenta
        if let index = modes.firstIndex(where: { $0.id == existingAss.id }) {
            modes[index].boundAppBundleIDs.removeAll(where: { $0 == conflictID })
        }
        
        // Dodaj do obecnego
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
}

struct PremiumLockView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var showLoginSheet: Bool
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(t("Your voice deserves more"))
                .font(.system(size: 24, weight: .bold))
            
            Text(t("Unlock advanced AI assistants, intelligent dictionaries, and custom snippets to turn every recording into polished, ready-to-use text. Everything is 100% free and runs fully offline on your computer — your data is secure, and the app collects no information."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            Button(action: {
                showLoginSheet = true
            }) {
                Text(t("Log In"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.top, 10)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// Przycisk menu z efektem hover i zaznaczenia
struct MenuButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : .primary.opacity(0.8))
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : .primary.opacity(0.8))
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(colorScheme == .dark ? Color.black : Color.white)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white : Color.black)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false) // Wyłączenie focusu
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct ThemeTile: View {
    let title: String
    let theme: String
    @Binding var currentTheme: String
    
    var body: some View {
        let isSelected = currentTheme == theme
        
        Button(action: {
            currentTheme = theme
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(previewBgColor)
                    
                    HStack(spacing: 0) {
                        // Sidebar
                        Rectangle()
                            .fill(previewSidebarColor)
                            .frame(width: 40)
                            .overlay(
                                VStack(alignment: .leading, spacing: 6) {
                                    Circle().fill(previewTextColor.opacity(0.5)).frame(width: 10, height: 10)
                                    RoundedRectangle(cornerRadius: 2).fill(previewTextColor.opacity(0.3)).frame(width: 25, height: 4)
                                    RoundedRectangle(cornerRadius: 2).fill(previewTextColor.opacity(0.3)).frame(width: 20, height: 4)
                                    Spacer()
                                }
                                .padding(6)
                            )
                        
                        // Content
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(previewTextColor.opacity(0.1))
                                .frame(height: 15)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(previewTextColor.opacity(0.1))
                                .frame(height: 30)
                            Spacer()
                        }
                        .padding(10)
                    }
                }
                .frame(height: 100)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(15)
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var previewBgColor: Color {
        switch theme {
        case "light": return .white
        case "dark": return Color(red: 0.15, green: 0.15, blue: 0.15)
        case "system":
            let isSystemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return isSystemDark ? Color(red: 0.15, green: 0.15, blue: 0.15) : .white
        default: return .white
        }
    }
    
    private var previewSidebarColor: Color {
        switch theme {
        case "light": return Color(red: 0.9, green: 0.9, blue: 0.9)
        case "dark": return Color(red: 0.1, green: 0.1, blue: 0.1)
        case "system":
            let isSystemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return isSystemDark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color(red: 0.9, green: 0.9, blue: 0.9)
        default: return Color(red: 0.9, green: 0.9, blue: 0.9)
        }
    }
    
    private var previewTextColor: Color {
        switch theme {
        case "light": return .black
        case "dark": return .white
        case "system":
            let isSystemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return isSystemDark ? .white : .black
        default: return .white
        }
    }
}

struct HomeSettingsView: View {
    @Environment(\.colorScheme) var appColorScheme
    @ObservedObject var localizer = LocalizationManager.shared
    @AppStorage("autoLearnDictionary") private var autoLearnDictionary = false
    @AppStorage("hotkeyString") private var hotkeyString = "Cmd + Shift + `"
    @AppStorage("hotkeyMode") private var hotkeyMode: HotkeyMode = .click
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("playAnySound") private var playAnySound = true
    @AppStorage("playSound_Start") private var playSound_Start = true
    @AppStorage("playSound_Error") private var playSound_Error = true
    @AppStorage("playSound_End") private var playSound_End = true
    
    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any?
    @State private var lastModifierPressed: UInt16? = nil
    
    @State private var audioDevices: [AudioDevice] = []
    @AppStorage("selectedAudioDeviceUID") private var selectedDeviceUID = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                Text(t("Settings"))
                    .font(.system(size: 28, weight: .bold))
            }
            
            appThemeSection
            appLanguageSection
            keyboardShortcutSection
            audioSourceSection
            appSoundsSection
            autoUpdateDictionarySection
        }
        .onAppear {
            setupEventMonitor()
            DispatchQueue.global(qos: .userInitiated).async {
                let devices = AudioManager().getAudioInputDevices()
                DispatchQueue.main.async {
                    self.audioDevices = devices
                }
            }
        }
        .onDisappear {
            removeEventMonitor()
        }
    }
    
    @ViewBuilder
    private var keyboardShortcutSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("Keyboard Shortcut"))
                .font(.system(size: 16, weight: .semibold))
            
            HStack(spacing: 15) {
                Button(action: { hotkeyMode = .click }) {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.point.up.fill")
                            .font(.system(size: 20))
                        Text(t("Click"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(hotkeyMode == .click ? Color.primary.opacity(0.1) : Color.clear)
                    .cornerRadius(10)
                    .contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(hotkeyMode == .click ? Color.primary : Color.primary.opacity(0.2), lineWidth: hotkeyMode == .click ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: { hotkeyMode = .hold }) {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 20))
                        Text(t("Hold"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(hotkeyMode == .hold ? Color.primary.opacity(0.1) : Color.clear)
                    .cornerRadius(10)
                    .contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(hotkeyMode == .hold ? Color.primary : Color.primary.opacity(0.2), lineWidth: hotkeyMode == .hold ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .background(Color.white.opacity(0.05))
            
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Listening activation key"))
                    .font(.system(size: 16, weight: .bold))
                
                Button(action: {
                    isRecordingHotkey.toggle()
                    if isRecordingHotkey {
                        HotkeyManager.shared.stopListening()
                    } else {
                        HotkeyManager.shared.startListening()
                    }
                }) {
                    let isDark = appColorScheme == .dark
                    HStack {
                        Text(isRecordingHotkey ? t("Press keys...") : hotkeyString)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(isRecordingHotkey ? (isDark ? .black : .white) : .primary)
                        Spacer()
                        Image(systemName: "keyboard")
                            .font(.system(size: 20))
                            .foregroundColor(isRecordingHotkey ? (isDark ? .black : .white) : .secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 15)
                    .background(isRecordingHotkey ? (isDark ? .white : .black) : Color.primary.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isRecordingHotkey ? (isDark ? .white : .black) : Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var audioSourceSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("Audio source"))
                .font(.system(size: 16, weight: .semibold))
            
            HStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                Text(t("Select microphone:"))
                    .font(.system(size: 13))
                Spacer()
                
                Picker("", selection: $selectedDeviceUID) {
                    Text(t("Default system")).tag("")
                    ForEach(audioDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.system(size: 13))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var appSoundsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("App sounds"))
                .font(.system(size: 16, weight: .semibold))
            
            Toggle(t("Play sounds"), isOn: $playAnySound)
                .toggleStyle(CustomToggleStyle())
                .font(.system(size: 14, weight: .bold))
                .fixedSize()
            
            if playAnySound {
                Divider()
                    .background(Color.white.opacity(0.05))
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(t("Recording start"), isOn: $playSound_Start)
                        .toggleStyle(CustomToggleStyle())
                        .font(.system(size: 12))
                        .fixedSize()
                    
                    Toggle(t("Error / Not recognized"), isOn: $playSound_Error)
                        .toggleStyle(CustomToggleStyle())
                        .font(.system(size: 12))
                        .fixedSize()
                    
                    Toggle(t("End (Success)"), isOn: $playSound_End)
                        .toggleStyle(CustomToggleStyle())
                        .font(.system(size: 12))
                        .fixedSize()
                }
                .padding(.leading, 5)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var autoUpdateDictionarySection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("Auto-update dictionary"))
                .font(.system(size: 16, weight: .semibold))
            
            Toggle(isOn: $autoLearnDictionary) {
                Text(t("Enable automatic learning of corrections"))
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .accentColor(appColorScheme == .dark ? .white : .black)
            .tint(appColorScheme == .dark ? .white : .black)
            
            Text(t("If you correct the entered text within 10 seconds, the app will automatically add this correction to the dictionary."))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var appThemeSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("App Theme"))
                .font(.system(size: 16, weight: .semibold))
            
            HStack(spacing: 15) {
                ThemeTile(title: t("System"), theme: "system", currentTheme: $appTheme)
                ThemeTile(title: t("Light"), theme: "light", currentTheme: $appTheme)
                ThemeTile(title: t("Dark"), theme: "dark", currentTheme: $appTheme)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var appLanguageSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("App Language"))
                .font(.system(size: 16, weight: .semibold))
            
            HStack {
                Text(t("App Language"))
                    .font(.system(size: 13))
                Spacer()
                
                Picker("", selection: $localizer.appLanguage) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Italiano").tag("it")
                    Text("日本語").tag("ja")
                    Text("Polski").tag("pl")
                    Text("Português").tag("pt")
                    Text("中文").tag("zh")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.system(size: 13))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func setupEventMonitor() {
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if isRecordingHotkey {
                if event.type == .flagsChanged {
                    let keyCode = event.keyCode
                    let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
                    
                    if modifierKeyCodes.contains(keyCode) {
                        let modifiers = event.modifierFlags
                        var isPressed = false
                        
                        switch keyCode {
                        case 54, 55: isPressed = modifiers.contains(.command)
                        case 56, 60: isPressed = modifiers.contains(.shift)
                        case 58, 61: isPressed = modifiers.contains(.option)
                        case 59, 62: isPressed = modifiers.contains(.control)
                        case 63: isPressed = modifiers.contains(.function)
                        default: break
                        }
                        
                        if isPressed {
                            lastModifierPressed = keyCode
                        } else {
                            // Release
                            if keyCode == lastModifierPressed {
                                var str = ""
                                switch keyCode {
                                case 54, 55: str = "Command"
                                case 56, 60: str = "Shift"
                                case 58, 61: str = "Option"
                                case 59, 62: str = "Control"
                                case 63: str = "Fn"
                                default: break
                                }
                                
                                UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyCode")
                                UserDefaults.standard.set(0, forKey: "hotkeyModifiers")
                                UserDefaults.standard.set(str, forKey: "hotkeyString")
                                
                                isRecordingHotkey = false
                                HotkeyManager.shared.startListening()
                                
                                lastModifierPressed = nil
                                return nil // Swallow event
                            }
                            lastModifierPressed = nil
                        }
                    }
                    return event
                }
                
                if event.type == .keyDown {
                    lastModifierPressed = nil // Clear state on any key down
                    
                    let keyCode = event.keyCode
                    
                    // Escape (kod 53) anuluje nagrywanie
                    if keyCode == 53 {
                        print("🛑 Nagrywanie skrótu anulowane przez Escape")
                        isRecordingHotkey = false
                        HotkeyManager.shared.startListening() // Przywróć nasłuchiwanie globalnego skrótu
                        return nil // Przechwyć zdarzenie, nie przekazuj dalej
                    }
                    
                    let modifiers = event.modifierFlags
                    
                    // Sprawdź czy są modyfikatory dla zwykłych klawiszy
                    let hasModifiers = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control)
                    
                    // Lista kodów klawiszy funkcyjnych (Esc=53, F1-F12=122,120..., Strzałki=123-126, Space=49)
                    let functionKeyCodes: Set<UInt16> = [53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 123, 124, 125, 126, 49]
                    let isFunctionKey = functionKeyCodes.contains(keyCode)
                    
                    if !hasModifiers && !isFunctionKey {
                        print("⚠️ Zwykłe klawisze muszą być używane z modyfikatorem!")
                        return event // Ignoruj, czekaj na poprawny skrót
                    }
                    
                    // Map Cocoa modifiers to Carbon modifiers
                    var carbonModifiers: UInt32 = 0
                    if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
                    if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
                    if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
                    if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
                    
                    // Save to UserDefaults
                    UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyCode")
                    UserDefaults.standard.set(Int(carbonModifiers), forKey: "hotkeyModifiers")
                    
                    // Update string representation
                    var str = ""
                    if modifiers.contains(.command) { str += "Cmd + " }
                    if modifiers.contains(.shift) { str += "Shift + " }
                    if modifiers.contains(.option) { str += "Opt + " }
                    if modifiers.contains(.control) { str += "Ctrl + " }
                    
                    let keyChar = event.charactersIgnoringModifiers?.first ?? "`"
                    str += String(keyChar).uppercased()
                    
                    UserDefaults.standard.set(str, forKey: "hotkeyString")
                    
                    isRecordingHotkey = false
                    
                    // Restart HotkeyManager!
                    HotkeyManager.shared.startListening()
                    
                    return nil // Swallow event
                }
                return event
            }
            return event
        }
    }
    
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
    }
}

struct StatisticsView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var localizer = LocalizationManager.shared
    @State private var stats: [UsageStat] = []
    @AppStorage("isIncognitoMode") private var isIncognitoMode = false
    @ObservedObject private var memoryManager = MessageMemoryManager.shared
    @State private var isShowingBenchmarkSheet = false
    @State private var isShowingIncognitoExplanation = false
    @State private var isShowingExplanationFromInfoButton = false

    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            headerView
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                    Text(t("Statistics"))
                        .font(.system(size: 20, weight: .bold))
                }
                heroBannerView
                summaryCardsView
                chartsView
            }
            .padding(.top, 10)
            
            Divider()
                .padding(.vertical, 10)
            
            VStack(alignment: .leading, spacing: 10) {
                ramHistoryView
            }
        }
        .sheet(isPresented: $isShowingBenchmarkSheet) {
            BenchmarkView()
        }
        .sheet(isPresented: $isShowingIncognitoExplanation) {
            IncognitoExplanationView(isFromInfo: isShowingExplanationFromInfoButton)
        }
        .onAppear {
            loadStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UsageStatsUpdated"))) { _ in
            loadStats()
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Image(systemName: "house.fill")
                .font(.system(size: 24))
                .foregroundColor(.primary)
            Text(t("Home"))
                .font(.system(size: 28, weight: .bold))
            Spacer()
            
            // Tryb incognito
            HStack(spacing: 8) {
                Button(action: {
                    isShowingExplanationFromInfoButton = true
                    isShowingIncognitoExplanation = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(t("Learn more about incognito mode"))
                
                Toggle(t("Incognito Mode"), isOn: Binding(
                    get: { isIncognitoMode },
                    set: { newValue in
                        isIncognitoMode = newValue
                        if newValue {
                            if !UserDefaults.standard.bool(forKey: "skipIncognitoExplanation") {
                                isShowingExplanationFromInfoButton = false
                                isShowingIncognitoExplanation = true
                            }
                        }
                    }
                ))
                .toggleStyle(CustomToggleStyle())
                .font(.system(size: 16, weight: .bold))
                .fixedSize()
                .help(t("In incognito mode, no statistics or RAM text history are saved."))
            }
        }
    }
    
    @ViewBuilder
    private var heroBannerView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .font(.system(size: 16))
                    Text(t("PRODUCTIVITY GAIN"))
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .tracking(1)
                }
                
                Text(String(format: t("You have already saved %@"), formatDuration(totalSavedTime)))
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.primary)
                
                Text(t("Voice typing in Sonor is on average 3.5x faster than typing on a keyboard. Thanks to this, you got back valuable time for more important tasks."))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button(action: {
                    isShowingBenchmarkSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.needle.fill")
                        Text(t("Test it yourself (Speed Test)"))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            
            Spacer()
            
            // Visual Circle Progress
            VStack(spacing: 8) {
                let progress = milestoneProgress
                let percent = Int(progress * 100)
                ZStack {
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            colorScheme == .dark ? Color.white : Color.black,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 2) {
                        Text("\(percent)%")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.primary)
                        Text(t("of goal"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(nextMilestone.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.trailing, 10)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var summaryCardsView: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(
                title: t("AVERAGE SPEECH PACE"),
                value: String(format: t("%.0f words/min"), averageSpeechSpeed > 0 ? averageSpeechSpeed : 140.0),
                subtitle: t("Standard typing: ~40 words/min"),
                icon: "speedometer"
            )
            StatCard(
                title: t("TOTAL SPOKEN WORDS"),
                value: String(format: t("%d words"), totalWords),
                subtitle: String(format: t("Approx. %d A4 pages without keyboard"), pagesSaved),
                icon: "bubble.left.and.bubble.right.fill"
            )
            StatCard(
                title: t("SPEAKING TIME"),
                value: formatDuration(totalSpeakingTime),
                subtitle: t("Active recording time"),
                icon: "mic.fill"
            )
            StatCard(
                title: t("NUMBER OF RECORDINGS"),
                value: String(format: t("%d sessions"), stats.count),
                subtitle: t("Transcriptions done locally"),
                icon: "waveform"
            )
        }
    }
    
    @ViewBuilder
    private var activityChart: some View {
        ActivityChartView(dailyStats: dailyStats, colorScheme: colorScheme)
    }

    @ViewBuilder
    private var paceChart: some View {
        PaceChartView(dailyStats: dailyStats, colorScheme: colorScheme)
    }

    @ViewBuilder
    private var chartsView: some View {
        Group {
            if dailyStats.count > 0 {
                HStack(spacing: 20) {
                    activityChart
                    paceChart
                }
            } else {
                VStack(alignment: .center, spacing: 15) {
                    Text(t("No activity data to display"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
    }

    @ViewBuilder
    private var ramHistoryView: some View {
        RamHistoryView(memoryManager: memoryManager, colorScheme: colorScheme)
    }
    
    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: "usageStats"),
           let decoded = try? JSONDecoder().decode([UsageStat].self, from: data) {
            self.stats = decoded
        }
    }
    
    private var totalSpeakingTime: Double {
        stats.reduce(0) { $0 + $1.duration }
    }
    
    private var totalWords: Int {
        stats.reduce(0) { $0 + $1.wordCount }
    }
    
    private var totalSavedTime: Double {
        let typingTimeSeconds = (Double(totalWords) / 40.0) * 60.0
        return max(0.0, typingTimeSeconds - totalSpeakingTime)
    }
    
    private var averageSpeechSpeed: Double {
        guard totalSpeakingTime > 0 else { return 0 }
        return Double(totalWords) / (totalSpeakingTime / 60)
    }
    
    private var pagesSaved: Int {
        totalWords / 250
    }
    
    private var nextMilestone: (seconds: Double, label: String) {
        let hour = 3600.0
        let currentHours = totalSavedTime / hour
        
        let milestoneHours: Double
        if currentHours < 1.0 {
            milestoneHours = 1.0
        } else if currentHours < 5.0 {
            // Kamienie milowe co 1 godzinę (2.0, 3.0, 4.0, 5.0)
            milestoneHours = ceil(currentHours)
        } else if currentHours < 20.0 {
            // Kamienie milowe co 2,5 godziny (7.5, 10.0, 12.5, 15.0, 17.5, 20.0)
            let step = 2.5
            milestoneHours = ceil(currentHours / step) * step
        } else if currentHours < 50.0 {
            // Kamienie milowe co 5 godzin (25.0, 30.0, 35.0, 40.0, 45.0, 50.0)
            let step = 5.0
            milestoneHours = ceil(currentHours / step) * step
        } else if currentHours < 100.0 {
            // Kamienie milowe co 10 godzin (60.0, 70.0, 80.0, 90.0, 100.0)
            let step = 10.0
            milestoneHours = ceil(currentHours / step) * step
        } else {
            // Powyżej 100 godzin: kamienie milowe co 25 godzin (125.0, 150.0, 175.0, 200.0 itd.)
            let step = 25.0
            milestoneHours = ceil(currentHours / step) * step
        }
        
        let label: String
        let lang = LocalizationManager.shared.appLanguage
        if lang != "pl" {
            let suffix: String
            switch lang {
            case "de":
                suffix = milestoneHours == 1.0 ? "Stunde" : "Stunden"
                label = "Ziel: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours)) \(suffix)"
            case "es":
                suffix = milestoneHours == 1.0 ? "hora" : "horas"
                label = "Objetivo: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours)) \(suffix)"
            case "fr":
                suffix = milestoneHours == 1.0 ? "heure" : "heures"
                label = "Objectif: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours)) \(suffix)"
            case "it":
                suffix = milestoneHours == 1.0 ? "ora" : "ore"
                label = "Obiettivo: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours)) \(suffix)"
            case "pt":
                suffix = milestoneHours == 1.0 ? "hora" : "horas"
                label = "Objetivo: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours)) \(suffix)"
            case "ja":
                suffix = "時間"
                label = "目標: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours))\(suffix)"
            default: // en
                suffix = milestoneHours == 1.0 ? "hour" : "hours"
                label = "Goal: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours)) \(suffix)"
            }
        } else {
            if milestoneHours == 1.0 {
                label = t("Goal: 1 hour")
            } else {
                let suffix: String
                if milestoneHours.truncatingRemainder(dividingBy: 1.0) != 0 {
                    suffix = "godziny"
                } else {
                    let hoursInt = Int(milestoneHours)
                    let lastDigit = hoursInt % 10
                    let lastTwoDigits = hoursInt % 100
                    let isGodziny = lastDigit >= 2 && lastDigit <= 4 && !(lastTwoDigits >= 12 && lastTwoDigits <= 14)
                    suffix = isGodziny ? "hours" : "hours (many)"
                }
                
                if milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 {
                    label = "Cel: \(Int(milestoneHours)) \(suffix)"
                } else {
                    label = "Cel: \(String(format: "%.1f", milestoneHours).replacingOccurrences(of: ".", with: ",")) \(suffix)"
                }
            }
        }
        
        return (milestoneHours * hour, label)
    }
    
    private var milestoneProgress: Double {
        let limit = nextMilestone.seconds
        return min(1.0, totalSavedTime / limit)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            return String(format: "%.1fm", seconds / 60)
        } else {
            return String(format: "%.1fh", seconds / 3600)
        }
    }
    

    
    private var dailyStats: [DailyStat] {
        let calendar = Calendar.current
        let statsArray = self.stats
        let grouped: [Date: [UsageStat]] = Dictionary(grouping: statsArray) { (stat: UsageStat) -> Date in
            return calendar.startOfDay(for: stat.date)
        }
        let mapped: [DailyStat] = grouped.map { (key: Date, value: [UsageStat]) -> DailyStat in
            let wordCountSum = value.reduce(0) { (sum: Int, stat: UsageStat) -> Int in
                return sum + stat.wordCount
            }
            let durationSum = value.reduce(0.0) { (sum: Double, stat: UsageStat) -> Double in
                return sum + stat.duration
            }
            return DailyStat(
                date: key,
                wordCount: wordCountSum,
                speakingTime: durationSum
            )
        }
        let sorted = mapped.sorted { (a: DailyStat, b: DailyStat) -> Bool in
            return a.date < b.date
        }
        return sorted
    }
}

fileprivate struct RamHistoryView: View {
    @ObservedObject var memoryManager: MessageMemoryManager
    let colorScheme: ColorScheme
    
    // Hover state trackers for RAM History
    @State private var hoveredCardId: UUID? = nil
    @State private var hoveredCopyId: UUID? = nil
    @State private var hoveredTrashId: UUID? = nil
    @State private var isHoveringClearHistory = false
    @State private var isShowingRamExplanation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(t("Text History (RAM only)"))
                        .font(.system(size: 20, weight: .bold))
                    
                    Button(action: {
                        isShowingRamExplanation = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(t("Learn more about RAM history"))
                }
                Spacer()
                if !memoryManager.messages.isEmpty {
                    Button(action: {
                        withAnimation {
                            memoryManager.clearHistory()
                        }
                    }) {
                        Text(t("Clear history"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(isHoveringClearHistory ? .white : .red)
                            .background(isHoveringClearHistory ? Color.red : Color.clear)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red, lineWidth: 1)
                            )
                            .animation(.easeInOut(duration: 0.15), value: isHoveringClearHistory)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringClearHistory = hovering
                    }
                }
            }
            
            if memoryManager.messages.isEmpty {
                // Modern empty state with dashed borders and clock icon
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(t("No saved texts in RAM"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(t("Every processed text will appear here temporarily. Closing Sonor or clearing the history will permanently delete this data."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [5, 5], dashPhase: 0))
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(memoryManager.messages.reversed()) { msg in
                            MessageCardView(
                                msg: msg,
                                colorScheme: colorScheme,
                                isCardHovered: hoveredCardId == msg.id,
                                isCopyHovered: hoveredCopyId == msg.id,
                                isTrashHovered: hoveredTrashId == msg.id,
                                onCopyHover: { hovering in
                                    hoveredCopyId = hovering ? msg.id : nil
                                },
                                onDeleteHover: { hovering in
                                    hoveredTrashId = hovering ? msg.id : nil
                                },
                                onCardHover: { hovering in
                                    hoveredCardId = hovering ? msg.id : nil
                                },
                                onDelete: {
                                    memoryManager.deleteMessage(id: msg.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 400) // Ograniczenie wysokości listy
            }
        }
        .sheet(isPresented: $isShowingRamExplanation) {
            RamHistoryExplanationView()
        }
    }
}

struct RamHistoryExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Upper padding spacer instead of X close button
            Spacer()
                .frame(height: 30)
            
            // Icon & Title
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t("Text History Privacy"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Stored only in RAM"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("The text history is saved exclusively in the computer's operational memory (RAM), not on the disk."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Completely temporary"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("All saved texts disappear immediately when you close the application. They are not recoverable, ensuring your data remains private."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Local processing"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("We do not store, send, or analyze your processed texts anywhere outside of your device."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Text(t("I understand"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 420)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

fileprivate struct MessageCardView: View {
    let msg: MemoryMessage
    let colorScheme: ColorScheme
    let isCardHovered: Bool
    let isCopyHovered: Bool
    let isTrashHovered: Bool
    let onCopyHover: (Bool) -> Void
    let onDeleteHover: (Bool) -> Void
    let onCardHover: (Bool) -> Void
    let onDelete: () -> Void
    
    @State private var isCopied = false
    @State private var isExpanded = false
    
    private var copyBgColor: Color {
        if isCopyHovered {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
        } else {
            return Color.clear
        }
    }
    
    private var copyFgColor: Color {
        if isCopyHovered {
            return colorScheme == .dark ? Color.white : Color.black
        } else {
            return Color.secondary
        }
    }
    
    private var deleteBgColor: Color {
        if isTrashHovered {
            return Color.red.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    private var deleteFgColor: Color {
        if isTrashHovered {
            return Color.red
        } else {
            return Color.secondary
        }
    }
    
    private var cardBgColor: Color {
        if colorScheme == .dark {
            return isCardHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.025)
        } else {
            return isCardHovered ? Color.black.opacity(0.03) : Color.black.opacity(0.015)
        }
    }
    
    private var cardStrokeColor: Color {
        if isCardHovered {
            return colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(msg.date, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                // Premium interactive action buttons
                HStack(spacing: 6) {
                    // Copy button
                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(msg.text, forType: .string)
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isCopied = true
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isCopied = false
                            }
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(copyBgColor)
                                .frame(width: 26, height: 26)
                            
                            if isCopied {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.green)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(copyFgColor)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(t("Copy text"))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onCopyHover(hovering)
                        }
                    }
                    
                    // Delete button
                    Button(action: {
                        withAnimation {
                            onDelete()
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(deleteBgColor)
                                .frame(width: 26, height: 26)
                            
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(deleteFgColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(t("Delete entry"))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onDeleteHover(hovering)
                        }
                    }
                }
            }
            
            // Text content
            Text(msg.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineSpacing(3)
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                onCardHover(hovering)
            }
        }
    }
}

fileprivate struct DailyStat: Identifiable {
    let id = UUID()
    let date: Date
    let wordCount: Int
    let speakingTime: Double // seconds
    
    var savedTimeMinutes: Double {
        let typingTimeMinutes = Double(wordCount) / 40.0
        let speakingTimeMinutes = speakingTime / 60.0
        return max(0.0, typingTimeMinutes - speakingTimeMinutes)
    }
    
    var averageWPM: Double {
        guard speakingTime > 0 else { return 0 }
        return Double(wordCount) / (speakingTime / 60.0)
    }
}

fileprivate struct ActivityChartView: View {
    let dailyStats: [DailyStat]
    let colorScheme: ColorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("Activity (Words)"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
            
            Chart(dailyStats) { day in
                BarMark(
                    x: .value("Dzień", day.date, unit: .day),
                    y: .value("Słowa", day.wordCount)
                )
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .cornerRadius(12)
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

fileprivate struct PaceChartView: View {
    let dailyStats: [DailyStat]
    let colorScheme: ColorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("Speech Pace (WPM)"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
            
            Chart(dailyStats) { day in
                LineMark(
                    x: .value("Dzień", day.date, unit: .day),
                    y: .value("WPM", day.averageWPM)
                )
                .symbol(Circle())
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .interpolationMethod(.monotone)
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

struct BenchmarkView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var audioManager = AudioManager()
    @ObservedObject private var localizer = LocalizationManager.shared
    
    @State private var step: Int = 0 // 0: Intro, 1: Writing, 2: Speaking, 3: Summary
    @State private var currentText: String = ""
    @State private var lastTextIndex: Int = -1
    
    // Writing test
    @State private var typedText: String = ""
    @State private var writingTimer: Timer?
    @State private var writingElapsed: Double = 0.0
    @State private var isWritingStarted: Bool = false
    @State private var isWritingFinished: Bool = false
    
    // Speaking test
    @State private var speakingTimer: Timer?
    @State private var speakingElapsed: Double = 0.0
    @State private var isSpeakingStarted: Bool = false
    @State private var isSpeakingFinished: Bool = false
    @State private var waveLevels: [CGFloat] = Array(repeating: 0.01, count: 36)
    
    @State private var isCloseHovered = false
    
    var presets: [String] {
        let lang = localizer.appLanguage
        switch lang {
        case "en":
            return [
                "Fast typing on a keyboard requires focus, but speaking allows you to express your thoughts freely in a fraction of a second without effort.",
                "Speech recognition technology is completely changing how we interact with text every day, saving valuable time.",
                "In today's busy world, every single minute counts, making local voice transcription an essential tool for productivity.",
                "Creating notes, writing emails, and capturing ideas has never been so simple and secure, as all data remains offline.",
                "Switching to voice typing helps relieve tension in your hands and spine while giving you full creative freedom and speed."
            ]
        case "de":
            return [
                "Schnelles Tippen auf einer Tastatur erfordert Konzentration, aber das Sprechen ermöglicht es Ihnen, Ihre Gedanken mühelos auszudrücken.",
                "Die Spracherkennungstechnologie revolutioniert die Art und Weise, wie wir täglich mit Texten arbeiten, und spart wertvolle Zeit.",
                "In der heutigen hektischen Welt zählt jede Minute, weshalb die lokale Sprachtranskription zu einem unverzichtbaren Werkzeug wird.",
                "Das Erstellen von Notizen, das Schreiben von E-Mails und das Festhalten von Ideen war noch nie so einfach und sicher, da alle Daten offline bleiben.",
                "Der Wechsel zur Spracheingabe entlastet Hände und Wirbelsäule und bietet gleichzeitig volle kreative Freiheit und erstaunliche Geschwindigkeit."
            ]
        case "es":
            return [
                "Escribir rápido en un teclado requiere concentración, pero hablar te permite expresar tus pensamientos libremente en una fracción de segundo.",
                "La tecnología de reconocimiento de voz revoluciona la forma en que trabajamos con el texto cada día, ahorrando un tiempo valioso.",
                "En el ajetreado mundo de hoy, cada minuto vale su peso en oro, por lo que la transcripción de voz local se convierte en una herramienta clave.",
                "Crear notas, escribir correos electrónicos y plasmar ideas nunca ha sido tan sencillo y seguro, ya que todos los datos permanecen fuera de línea.",
                "Pasar al dictado por voz ayuda a aliviar la tensión en las manos y la espalda, a la vez que ofrece total libertad creativa y gran rapidez."
            ]
        case "fr":
            return [
                "Taper rapidement sur un clavier demande de la concentration, mais parler vous permet d'exprimer vos pensées librement en un clin d'œil.",
                "La technologie de reconnaissance vocale révolutionne notre façon de travailler avec le texte au quotidien, nous faisant gagner un temps précieux.",
                "Dans notre monde moderne très actif, chaque minute compte, c'est pourquoi la transcription vocale locale devient un outil essentiel.",
                "Prendre des notes, rédiger des e-mails et coucher ses idées sur papier n'a jamais été aussi simple et sécurisé, car les données restent hors ligne.",
                "Passer à la saisie vocale permet de soulager vos mains et votre dos, tout en vous offrant une liberté créative totale et une vitesse incroyable."
            ]
        case "it":
            return [
                "Digitare rapidamente su una tastiera richiede concentrazione, ma parlare ti consente di esprimere i tuoi pensieri liberamente in pochi istanti.",
                "La tecnologia di riconoscimento vocale sta rivoluzionando il modo in che lavoriamo con i testi ogni giorno, facendoci risparmiare tempo prezioso.",
                "Nel mondo frenetico di oggi, ogni singolo minuto è prezioso, il che rende la trascrizione vocale locale uno strumento davvero fondamentale.",
                "Prendere appunti, scrivere e-mail e registrare idee non é mai stato così semplice e sicuro, poiché tutti i dati rimangono offline.",
                "Passare alla digitazione vocale aiuta ad alleviare la tensione a mani e schiena, offrendo al contempo massima libertà creativa e rapidità."
            ]
        case "ja":
            return [
                "キーボードでの高速入力には集中力が必要ですが、話すことで瞬時に何の努力もなく自由に考えを表現することができます。",
                "音声認識技術は、私たちが毎日テキストを扱う方法を根本から変え、貴重な時間を大幅に節約してくれます。",
                "今日の忙しい世界では、一分一秒が非常に貴重であり、そのためローカルでの音声文字起こしが極めて重要なツールとなっています。",
                "すべてのデータがオフラインで保存されるため、メモの作成、メールの執筆、アイデアの記録がかつてないほど簡単かつ安全になります。",
                "音声入力に切り替えることで、手や背中の負担を軽減しながら、同時に完全な創作の自由と圧倒的な処理スピードが得られます。"
            ]
        case "pt":
            return [
                "Digitar rapidamente no teclado exige concentração, mas falar permite que você expresse seus pensamentos livremente em uma fração de segundo.",
                "A tecnologia de reconhecimento de voz revoluciona a maneira como trabalhamos com texto todos os dias, economizando um tempo valioso.",
                "No mundo agitado de hoje, cada minuto vale ouro, e por isso a transcrição de voz local está se tornando uma ferramenta indispensável.",
                "Criar notas, escrever e-mails e registrar ideias nunca foi tão simples e seguro, pois todos os dados permanecem totalmente offline.",
                "Mudar para a digitação por voz ajuda a aliviar a tensão nas mãos e nas costas, proporcionando total liberdade criativa e velocidade incrível."
            ]
        default:
            return [
                "Szybkie pisanie na klawiaturze wymaga skupienia, ale mówienie pozwala na swobodne wyrażanie myśli w ułamku sekundy bez wysiłku.",
                "Technologia rozpoznawania mowy rewolucjonizuje sposób, w jaki pracujemy z tekstem każdego dnia, oszczędzając cenny czas.",
                "W dzisiejszym zabieganym świecie każda minuta jest na wagę złota, dlatego lokalna transkrypcja głosu staje się kluczowym narzędziem.",
                "Tworzenie notatek, pisanie e-maili i spisywanie pomysłów nigdy nie było tak proste i bezpieczne, ponieważ wszystkie dane pozostają offline.",
                "Przejście na pisanie głosowe pozwala odciążyć dłonie i kręgosłup, dając jednocześnie pełną swobodę twórczą i niesamowitą prędkość działania."
            ]
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(t("Typing vs Speaking Speed Test"))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isCloseHovered ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                    .onTapGesture {
                        stopAllTimers()
                        dismiss()
                    }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
            
            // Scrollable Content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 1).id("topOfScrollContent")
                        if step == 0 {
                            introContentView
                        } else if step == 1 {
                            writingContentView
                        } else if step == 2 {
                            speakingContentView
                        } else if step == 3 {
                            summaryContentView
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }
                .onChange(of: isWritingFinished) { finished in
                    if finished {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation {
                                proxy.scrollTo("writingTimeLabel", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: step) { _ in
                    proxy.scrollTo("topOfScrollContent", anchor: .top)
                }
            }
            
            // Fixed Bottom Action Buttons (Sticky)
            VStack(spacing: 0) {
                Divider()
                bottomButtonsView
                    .padding(24)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .frame(width: 550, height: 480)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onAppear {
            selectRandomText()
        }
        .onDisappear {
            stopAllTimers()
        }
    }
    
    private func selectRandomText() {
        var nextIndex = Int.random(in: 0..<presets.count)
        if presets.count > 1 {
            while nextIndex == lastTextIndex {
                nextIndex = Int.random(in: 0..<presets.count)
            }
        }
        lastTextIndex = nextIndex
        currentText = presets[nextIndex]
    }
    
    private func stopAllTimers() {
        writingTimer?.invalidate()
        writingTimer = nil
        speakingTimer?.invalidate()
        speakingTimer = nil
        _ = audioManager.stopRecording()
    }
    
    // MARK: - Content Views
    
    private var introContentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Don't just take our word for it."))
                    .font(.system(size: 22, weight: .black))
            }
            
            Text(t("Voice typing is on average 3.5x faster than keyboard typing. Run a quick test and prove it to yourself. See how much faster you can get your thoughts onto the screen."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineSpacing(4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Test instructions:"))
                    .font(.system(size: 14, weight: .bold))
                
                HStack(alignment: .top, spacing: 10) {
                    Text("1.")
                        .font(.system(size: 13, weight: .bold))
                    Text(t("First, retype the displayed text using your keyboard. The timer starts automatically when you begin typing."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Text("2.")
                        .font(.system(size: 13, weight: .bold))
                    Text(t("Then read the same text aloud. You will measure your speaking time."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Text("3.")
                        .font(.system(size: 13, weight: .bold))
                    Text(t("At the end you will see a detailed summary and find out how much time you save."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
    
    private var writingContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(t("STEP 1 OF 2: TYPING"))
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Text(String(format: t("Timer: %.1fs"), writingElapsed))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            
            Text(t("Retype the text below as fast as you can:"))
                .font(.system(size: 14, weight: .bold))
            
            Text(currentText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                        )
                )
            
            TextEditor(text: $typedText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(height: 100)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .disabled(isWritingFinished)
                .onChange(of: typedText) { newValue in
                    if !isWritingStarted && !newValue.isEmpty {
                        startWritingTimer()
                    }
                }
            
            if isWritingFinished {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .bold))
                    Text(String(format: t("Your typing time: %.1fs"), writingElapsed))
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.vertical, 8)
                .transition(.opacity)
                .id("writingTimeLabel")
            } else if !isWritingStarted {
                HStack {
                    Spacer()
                    Text(t("Start typing to auto-start the timer..."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    Text(t("Keep typing..."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var speakingContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(t("STEP 2 OF 2: SPEAKING"))
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Text(String(format: t("Timer: %.1fs"), speakingElapsed))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            
            Text(t("Read the same text aloud:"))
                .font(.system(size: 14, weight: .bold))
            
            Text(currentText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                        )
                )
            
            VStack {
                Spacer()
                
                if isSpeakingStarted && !isSpeakingFinished {
                    // Waveform visualization
                    HStack(spacing: 2) {
                        Spacer()
                        ForEach(0..<waveLevels.count, id: \.self) { index in
                            let level = waveLevels[index]
                            let barHeight = CGFloat(2 + (level * 350))
                            
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                                .frame(width: 3, height: min(barHeight, 40))
                        }
                        Spacer()
                    }
                    .frame(height: 40)
                    .transition(.opacity)
                } else if isSpeakingFinished {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .bold))
                        Text(String(format: t("Your recording time: %.1fs"), speakingElapsed))
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .transition(.opacity)
                } else {
                    HStack {
                        Spacer()
                        Text(t("Click the button below to start speaking..."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                Spacer()
            }
            .frame(minHeight: 150)
        }
    }
    
    private var summaryContentView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: writingElapsed > speakingElapsed ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Your test result"))
                    .font(.system(size: 20, weight: .black))
                
                if speakingElapsed < writingElapsed {
                    Text(String(format: t("Speaking was %.1fx faster than typing!"), speedFactor))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                } else if writingElapsed < speakingElapsed {
                    let slowFactor = speakingElapsed / max(0.1, writingElapsed)
                    Text(String(format: t("Speaking was %.1fx slower than typing!"), slowFactor))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                } else {
                    Text(t("Speaking and typing took exactly the same time!"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                // Writing box
                let isWritingWinner = writingElapsed <= speakingElapsed
                VStack(spacing: 8) {
                    Text(t("CLASSIC TYPING"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.1fs", writingElapsed))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    
                    Text(String(format: t("%.0f words/min"), Double(wpmWriting)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isWritingWinner ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                                    lineWidth: isWritingWinner ? 2 : 1
                                )
                        )
                )
                
                // Speaking box
                let isSpeakingWinner = speakingElapsed < writingElapsed
                VStack(spacing: 8) {
                    Text(t("VOICE TYPING"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(String(format: "%.1fs", speakingElapsed))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    
                    Text(String(format: t("%.0f words/min"), Double(wpmSpeaking)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isSpeakingWinner ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                                    lineWidth: isSpeakingWinner ? 2 : 1
                                )
                        )
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if speakingElapsed < writingElapsed {
                    Text(String(format: t("You saved %.1f seconds on just one short sentence!"), timeDifference))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(t("Imagine writing long emails, articles, or notes this way. Over a year, you reclaim entire days of free time, and the app works 100% locally without collecting any data."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                } else {
                    Text(t("Wait, what...? Are you sure you didn't cheat? 😉"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(t("You got an incredible keyboard score (or spoke in slow motion on purpose!). This is rare in everyday life — voice typing is usually 3.5x faster on average and saves a lot of energy for your hands. Try again, this time without going easy on the keyboard! 🚀"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Fixed Bottom Buttons View
    
    private var bottomButtonsView: some View {
        Group {
            if step == 0 {
                introBottomButtons
            } else if step == 1 {
                writingBottomButtons
            } else if step == 2 {
                speakingBottomButtons
            } else if step == 3 {
                summaryBottomButtons
            }
        }
    }
    
    private var introBottomButtons: some View {
        Button(action: {
            step = 1
        }) {
            Text(t("Start test"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(colorScheme == .dark ? Color.white : Color.black)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    
    private var writingBottomButtons: some View {
        Group {
            if !isWritingFinished {
                Button(action: {
                    finishWriting()
                }) {
                    Text(t("Finish"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isWritingStarted ? (colorScheme == .dark ? .black : .white) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isWritingStarted ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!isWritingStarted)
            } else {
                Button(action: {
                    step = 2
                }) {
                    Text(t("Next"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
    
    private var speakingBottomButtons: some View {
        Group {
            if !isSpeakingStarted {
                Button(action: {
                    startSpeaking()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                        Text(t("Start speaking"))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            } else if isSpeakingStarted && !isSpeakingFinished {
                Button(action: {
                    finishSpeaking()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text(t("Stop and finish"))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            } else {
                Button(action: {
                    step = 3
                }) {
                    Text(t("See summary"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
    
    private var summaryBottomButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                resetTest()
            }) {
                Text(t("Repeat with another text"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            Button(action: {
                stopAllTimers()
                dismiss()
            }) {
                Text(t("Close"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
        }
    }
    
    // MARK: - Logic
    
    private func startWritingTimer() {
        isWritingStarted = true
        writingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            writingElapsed += 0.1
        }
    }
    
    private func finishWriting() {
        writingTimer?.invalidate()
        writingTimer = nil
        isWritingFinished = true
    }
    
    private func startSpeaking() {
        isSpeakingStarted = true
        waveLevels = (0..<36).map { _ in CGFloat.random(in: 0.01...0.03) }
        try? audioManager.startRecording()
        speakingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            speakingElapsed += 0.05
            
            withAnimation(.spring(response: 0.08, dampingFraction: 0.6)) {
                let micLevel = CGFloat(audioManager.audioLevel)
                let time = Date().timeIntervalSinceReferenceDate
                
                waveLevels = (0..<36).map { i in
                    let amp = max(0.01, micLevel * 1.8)
                    let sine = sin(time * 10 + Double(i) * 0.25)
                    let noise = Double.random(in: 0.0...0.02)
                    let rawVal = abs(sine * amp) + noise
                    return CGFloat(max(0.01, min(0.12, rawVal)))
                }
            }
        }
    }
    
    private func finishSpeaking() {
        speakingTimer?.invalidate()
        speakingTimer = nil
        isSpeakingFinished = true
        _ = audioManager.stopRecording()
    }
    
    private func resetTest() {
        stopAllTimers()
        step = 1
        typedText = ""
        writingElapsed = 0.0
        isWritingStarted = false
        isWritingFinished = false
        speakingElapsed = 0.0
        isSpeakingStarted = false
        isSpeakingFinished = false
        waveLevels = Array(repeating: 0.01, count: 36)
        selectRandomText()
    }
    
    // Stats calculations
    private var wordCount: Int {
        currentText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    
    private var wpmWriting: Double {
        guard writingElapsed > 0 else { return 0 }
        return Double(wordCount) / (writingElapsed / 60.0)
    }
    
    private var wpmSpeaking: Double {
        guard speakingElapsed > 0 else { return 0 }
        return Double(wordCount) / (speakingElapsed / 60.0)
    }
    
    private var speedFactor: Double {
        guard speakingElapsed > 0 else { return 1.0 }
        return writingElapsed / speakingElapsed
    }
    
    private var timeDifference: Double {
        max(0, writingElapsed - speakingElapsed)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

struct DictionarySettingsView: View {
    @ObservedObject var localizer = LocalizationManager.shared
    @State private var entries: [String: String] = [:]
    @State private var newWrong: String = ""
    @State private var newCorrect: String = ""
    @Environment(\.colorScheme) var colorScheme
    @State private var isHoveringAdd = false
    @State private var hoveredKey: String? = nil
    
    private var sortedKeys: [String] {
        entries.keys.sorted()
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                Text(t("Dictionary"))
                    .font(.system(size: 28, weight: .bold))
            }
            
            Text(t("Phonetic correction and automatic word replacement"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(t("Allows defining rules for replacing misheard words with correct formulations (e.g. proper names, industry abbreviations, or specific vocabulary). Works 100% locally."))
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.8))
                .lineSpacing(4)
        }
        .padding(.bottom, 8)
    }
    
    private var wrongInputView: some View {
        TextField(t("e.g. Superbase"), text: $newWrong)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
            )
    }
    
    private var correctInputView: some View {
        TextField(t("e.g. Supabase"), text: $newCorrect)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
            )
    }
    
    private var isAddButtonActive: Bool {
        !newWrong.isEmpty && !newCorrect.isEmpty
    }
    
    private var addButtonColor: Color {
        if isAddButtonActive {
            return colorScheme == .dark ? .white : .black
        } else {
            return Color.primary.opacity(0.1)
        }
    }
    
    private var addButtonView: some View {
        Button(action: addEntry) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isAddButtonActive ? (colorScheme == .dark ? .black : .white) : Color.primary.opacity(0.35))
                .frame(width: 38, height: 38)
                .background(addButtonColor)
                .cornerRadius(10)
                .scaleEffect(isHoveringAdd && isAddButtonActive ? 1.05 : 1.0)
                .animation(.spring(), value: isHoveringAdd)
        }
        .buttonStyle(.plain)
        .disabled(!isAddButtonActive)
        .onHover { hovering in
            isHoveringAdd = hovering
        }
    }
    
    private var addFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("ADD NEW CORRECTION"))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1)
            
            VStack(alignment: .leading, spacing: 6) {
                // Header labels row
                HStack(spacing: 16) {
                    Text(t("When it hears"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                        .frame(width: 20)
                    
                    Text(t("Replace with"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                        .frame(width: 38)
                }
                
                // Inputs row
                HStack(spacing: 16) {
                    wrongInputView
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 38)
                    
                    correctInputView
                    
                    addButtonView
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func rowView(key: String, value: String) -> some View {
        HStack(spacing: 20) {
            // Usłyszane
            VStack(alignment: .leading, spacing: 4) {
                Text(t("When it hears"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(key)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            // Poprawne
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Replace with (list)"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Delete button
            Button(action: { removeEntry(key: key) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredKey == key ? Color.red.opacity(0.1) : Color.clear)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(hoveredKey == key ? .red : .secondary)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if hovering {
                        hoveredKey = key
                    } else if hoveredKey == key {
                        hoveredKey = nil
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.01) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerView
            
            addFormView
            
            // List Header
            HStack {
                Text(String(format: t("SAVED CORRECTIONS (%d)"), entries.count))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.top, 8)
            
            // Entries List
            if entries.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(t("No dictionary entries"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(t("Add the first correction above to automatically fix the most common Sonor errors."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [5, 5], dashPhase: 0))
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedKeys, id: \.self) { key in
                        if let value = entries[key] {
                            rowView(key: key, value: value)
                        }
                    }
                }
            }
        }
        .onAppear(perform: loadEntries)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("VoiceModesUpdated"))) { _ in
            loadEntries()
        }
    }
    
    func loadEntries() {
        entries = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
    }
    
    func addEntry() {
        entries[newWrong] = newCorrect
        UserDefaults.standard.set(entries, forKey: "dictionaryEntries")
        newWrong = ""
        newCorrect = ""
    }
    
    func removeEntry(key: String) {
        withAnimation {
            entries.removeValue(forKey: key)
            UserDefaults.standard.set(entries, forKey: "dictionaryEntries")
        }
    }
}

struct SnippetsSettingsView: View {
    @State private var entries: [String: String] = [:]
    @State private var newShortcut: String = ""
    @State private var newExpansion: String = ""
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    @State private var isHoveringAdd = false
    @State private var hoveredKey: String? = nil
    
    private var sortedKeys: [String] {
        entries.keys.sorted()
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "scissors")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                Text(t("Snippets"))
                    .font(.system(size: 28, weight: .bold))
            }
            
            Text(t("Text shortcuts and message templates"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(t("They act like smart macros. The spoken keyword will be automatically replaced with long text, a URL, or a ready-made template."))
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.8))
                .lineSpacing(4)
        }
        .padding(.bottom, 8)
    }
    
    private var shortcutInputView: some View {
        TextField(t("e.g. youtube link"), text: $newShortcut)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
            )
    }
    
    private var expansionInputView: some View {
        TextField(t("e.g. https://youtube.com/c/SonorApp"), text: $newExpansion)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
            )
    }
    
    private var isAddButtonActive: Bool {
        !newShortcut.isEmpty && !newExpansion.isEmpty
    }
    
    private var addButtonColor: Color {
        if isAddButtonActive {
            return colorScheme == .dark ? .white : .black
        } else {
            return Color.primary.opacity(0.1)
        }
    }
    
    private var addButtonView: some View {
        Button(action: addEntry) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isAddButtonActive ? (colorScheme == .dark ? .black : .white) : Color.primary.opacity(0.35))
                .frame(width: 38, height: 38)
                .background(addButtonColor)
                .cornerRadius(10)
                .scaleEffect(isHoveringAdd && isAddButtonActive ? 1.05 : 1.0)
                .animation(.spring(), value: isHoveringAdd)
        }
        .buttonStyle(.plain)
        .disabled(!isAddButtonActive)
        .onHover { hovering in
            isHoveringAdd = hovering
        }
    }
    
    private var addFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("ADD NEW SNIPPET"))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1)
            
            VStack(alignment: .leading, spacing: 6) {
                // Header labels row
                HStack(spacing: 16) {
                    Text(t("Word shortcut"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                        .frame(width: 20)
                    
                    Text(t("Expand to text"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                        .frame(width: 38)
                }
                
                // Inputs row
                HStack(spacing: 16) {
                    shortcutInputView
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 38)
                    
                    expansionInputView
                    
                    addButtonView
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func rowView(key: String, value: String) -> some View {
        HStack(spacing: 20) {
            // Skrót
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Word shortcut"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(key)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: 160, alignment: .leading)
            
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            // Rozszerzenie
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Target text"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Delete button
            Button(action: { removeEntry(key: key) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredKey == key ? Color.red.opacity(0.1) : Color.clear)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(hoveredKey == key ? .red : .secondary)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if hovering {
                        hoveredKey = key
                    } else if hoveredKey == key {
                        hoveredKey = nil
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.01) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerView
            
            addFormView
            
            // List Header
            HStack {
                Text(String(format: t("SAVED SNIPPETS (%d)"), entries.count))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.top, 8)
            
            // Entries List
            if entries.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "scissors")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(t("No snippets"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(t("Add the first shortcut above to be able to use templates and automatically expand short forms."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [5, 5], dashPhase: 0))
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedKeys, id: \.self) { key in
                        if let value = entries[key] {
                            rowView(key: key, value: value)
                        }
                    }
                }
            }
        }
        .onAppear(perform: loadEntries)
    }
    
    func loadEntries() {
        entries = UserDefaults.standard.dictionary(forKey: "snippetsEntries") as? [String: String] ?? [:]
    }
    
    func addEntry() {
        entries[newShortcut] = newExpansion
        UserDefaults.standard.set(entries, forKey: "snippetsEntries")
        newShortcut = ""
        newExpansion = ""
    }
    
    func removeEntry(key: String) {
        entries.removeValue(forKey: key)
        UserDefaults.standard.set(entries, forKey: "snippetsEntries")
    }
}

struct ModesSettingsView: View {
    @Binding var modes: [VoiceMode]
    @Binding var selectedModeID: String
    @Binding var isShowingSidePanel: Bool
    @Environment(\.colorScheme) var colorScheme
    var isPremium: Bool
    @Binding var showLoginSheet: Bool
    @ObservedObject private var localizer = LocalizationManager.shared
    
    // Grid layout
    let columns = [
        GridItem(.adaptive(minimum: 160))
    ]
    
    @State private var isHoveringPlus = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.primary)
                    Text(t("Assistants"))
                        .font(.system(size: 28, weight: .bold))
                }
                Spacer()
                
                if isPremium {
                    Button(action: {
                        addNewMode()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text(t("Add Assistant"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .cornerRadius(20)
                        .scaleEffect(isHoveringPlus ? 1.05 : 1.0)
                        .animation(.spring(), value: isHoveringPlus)
                        .onHover { hovering in
                            isHoveringPlus = hovering
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            ScrollView {
                VStack(spacing: 15) {
                    if let rawOutput = modes.first(where: { $0.name == "Raw Output" }) ?? modes.first(where: { $0.name == "Zwykły output" }) {
                        ModeCard(
                            mode: rawOutput,
                            isSelected: selectedModeID == rawOutput.id.uuidString,
                            isPremium: true,
                            isRawOutput: true
                        ) {
                            selectedModeID = rawOutput.id.uuidString
                        } onSettings: {
                            selectedModeID = rawOutput.id.uuidString
                            withAnimation {
                                isShowingSidePanel = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    if !isPremium {
                        VStack(spacing: 14) {
                            VStack(spacing: 6) {
                                Text(t("Unlock new assistants after logging in"))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Text(t("Get access to advanced AI assistants (speech smoothing, professional emails, notes). Everything is 100% free, runs fully offline on your computer, and collects no data."))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            
                            Button(action: {
                                showLoginSheet = true
                            }) {
                                Text(t("Log In"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(colorScheme == .dark ? Color.white : Color.black)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                        .padding(.top, 10)
                    } else {
                        LazyVGrid(columns: columns, spacing: 15) {
                            ForEach(modes.filter { $0.name != "Raw Output" && $0.name != "Zwykły output" }) { mode in
                                ModeCard(
                                    mode: mode,
                                    isSelected: selectedModeID == mode.id.uuidString,
                                    isPremium: isPremium,
                                    isRawOutput: false
                                ) {
                                    selectedModeID = mode.id.uuidString
                                } onSettings: {
                                    selectedModeID = mode.id.uuidString
                                    withAnimation {
                                        isShowingSidePanel = true
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func addNewMode() {
        let newMode = VoiceMode(name: "New Assistant", prompt: "Enter your prompt here...", assistantType: "dictation")
        modes.append(newMode)
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: "voiceModes")
            NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
        }
        selectedModeID = newMode.id.uuidString
    }
}

struct ModeCard: View {
    let mode: VoiceMode
    let isSelected: Bool
    let isPremium: Bool
    let isRawOutput: Bool
    let onSelect: () -> Void
    let onSettings: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    @ObservedObject private var localizer = LocalizationManager.shared
    
    private var tagBgColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.black : Color.white
        } else {
            return colorScheme == .dark ? Color.white : Color.black
        }
    }
    
    private var tagFgColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white : Color.black
        } else {
            return colorScheme == .dark ? Color.black : Color.white
        }
    }
    
    private var descriptionText: String {
        if mode.isBuiltInMode {
            switch mode.name {
            case "Raw Output", "Zwykły output":
                return t("Performs pure 1:1 transcription of your speech, without any corrections or AI editing.")
            case "Text Smoothing", "Wygładzanie tekstu":
                return t("Removes stutters, repetitions, and grammatical errors and inserts appropriate punctuation. Preserves the original style, tone, and vocabulary of your statement.")
            case "Formal Email", "Formalny e-mail":
                return t("Automatically transforms loose thoughts into professional, elegant, and official business correspondence. Ideal for writing emails quickly.")
            case "Structured Note", "Ustrukturyzowana notatka":
                return t("Reorganizes dictated thoughts into an extremely neat text note. Uses spacing, indents, and traditional lists (e.g. 1., 2. or -).")
            default:
                return t("Built-in system assistant.")
            }
        } else {
            return mode.prompt.isEmpty ? t("Plain recording without a prompt.") : mode.prompt
        }
    }
    
    var body: some View {
        ZStack {
            // Main Card Content
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t(mode.name))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : .primary)
                    Spacer()
                    
                    if isRawOutput {
                        Text(t("Main Assistant"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(tagFgColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tagBgColor)
                            .cornerRadius(6)
                    }
                }
                
                Text(descriptionText)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .black.opacity(0.7) : .white.opacity(0.7)) : .secondary)
                    .lineLimit(isRawOutput ? 2 : 4)
                
                Spacer()
                
                HStack {
                    Image(systemName: mode.assistantType == "dictation" ? "pencil" : "wand.and.stars")
                        .font(.system(size: 12))
                    Text(mode.assistantType == "dictation" ? t("Dictation") : t("Editing"))
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    
                    if mode.pauseMusic {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(isSelected ? (colorScheme == .dark ? .black.opacity(0.7) : .white.opacity(0.7)) : .secondary)
            }
            .padding(15)
            .blur(radius: isPremium || isRawOutput ? 0 : 3.5)
            
            // Premium Lock Overlay
            if !isPremium && !isRawOutput {
                Color.black.opacity(0.2)
                    .cornerRadius(16)
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    Text("PREMIUM")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(5)
                }
            }
        }
        .frame(height: isRawOutput ? 120 : 160)
        .background(cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.gray : Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .scaleEffect(isHovered && (isPremium || isRawOutput) ? 1.02 : 1.0)
        .allowsHitTesting(isPremium || isRawOutput)
        .onHover { h in 
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = h
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            colorScheme == .dark ? Color.white : Color.black
        } else {
            Color.clear
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
    }
}

struct TrafficLight: View {
    let color: Color
    let icon: String
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.black.opacity(0.6))
                    .opacity(isHovered ? 1 : 0)
            )
            .onTapGesture {
                action()
            }
    }
}

struct CustomToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: 12)
                .fill(configuration.isOn ? (colorScheme == .dark ? Color.white : Color.black) : Color.primary.opacity(0.1))
                .frame(width: 40, height: 20)
                .overlay(
                    Circle()
                        .fill(configuration.isOn ? (colorScheme == .dark ? Color.black : Color.white) : Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

struct IncognitoExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    let isFromInfo: Bool
    @AppStorage("skipIncognitoExplanation") private var skipIncognitoExplanation = false
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Upper padding spacer instead of X close button
            Spacer()
                .frame(height: 30)
            
            // Icon & Title
            VStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t("Incognito Mode"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("No statistics"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("No information about speaking time, word count, or productivity gains is recorded."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("RAM memory only"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("Audio and transcription are processed exclusively in the computer's operational memory."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Immediate deletion"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("All data is irretrievably deleted from memory immediately after transcription finishes and text is pasted."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Checkbox (only if not opened from info button, or if opened from info button and is already checked so they can reset it)
            if !isFromInfo || skipIncognitoExplanation {
                Toggle(isOn: $skipIncognitoExplanation) {
                    Text(t("Do not show this notification again"))
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .accentColor(colorScheme == .dark ? .white : .black)
                .tint(colorScheme == .dark ? .white : .black)
                .focusable(false)
                .padding(.bottom, 16)
            }
            
            // Accept Button (Zrozumiałem)
            Button(action: {
                dismiss()
            }) {
                Text(t("I understand"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 430)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

// MARK: - Custom Modals for Models

struct ModelsRequiredExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)
            
            VStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t("Models Required"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Download necessary"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("In order to use Sonor and Whisper transcription, you must download the required AI models first in the Models tab."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Offline capability"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("Once downloaded, the models run 100% locally on your computer without internet access."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text(t("I understand"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .frame(width: 320, height: 380)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

struct ModelDownloadErrorView: View {
    let error: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)
            
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                
                Text(t("Download Interrupted"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Connection lost or timeout"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("The model download could not be completed. Network connection might be unstable."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.clockwise.icloud.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Safe to resume"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("You can safely resume the download later without losing progress."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text(t("I understand"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .frame(width: 320, height: 380)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

struct UserProfileView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var localizer = LocalizationManager.shared
    
    @State private var isCloseHovered = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil
    @State private var deletePassword = ""
    
    // Change Password States
    @State private var isChangingPassword = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var changePasswordError: String? = nil
    @State private var isSavingPassword = false
    @State private var showSuccessMessage = false
    
    private var formattedCreationDate: String {
        guard let date = authManager.currentUserCreatedAt else {
            return t("Loading...")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: localizer.appLanguage)
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with custom close button
            HStack {
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isCloseHovered ? .white : .secondary)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                    .onTapGesture {
                        dismiss()
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            if showSuccessMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text(t("Password Updated Successfully!"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(t("Your account is now secure with the new password."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .transition(.opacity)
                .onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            withAnimation {
                                showSuccessMessage = false
                                isChangingPassword = false
                            }
                        }
                    }
                }
            } else if isChangingPassword {
                VStack(spacing: 14) {
                    Text(t("Change Password"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Old password"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        SecureField(t("Enter old password..."), text: $oldPassword)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("New password"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        SecureField(t("Enter new password..."), text: $newPassword)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Repeat new password"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        SecureField(t("Repeat new password..."), text: $confirmNewPassword)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    
                    if let changePasswordError = changePasswordError {
                        Text(changePasswordError)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    if isSavingPassword {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 20)
                    } else {
                        // Save Button
                        Button(action: {
                            performPasswordChange()
                        }) {
                            Text(t("Save Password"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.horizontal, 24)
                        
                        // Cancel Button
                        Button(action: {
                            withAnimation {
                                isChangingPassword = false
                                oldPassword = ""
                                newPassword = ""
                                confirmNewPassword = ""
                                changePasswordError = nil
                            }
                        }) {
                            Text(t("Cancel"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    // Avatar
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    
                    // Premium tag if logged in
                    Text(t("PREMIUM"))
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white)
                        .cornerRadius(4)
                        .padding(.bottom, 16)
                    
                    // Email and date
                    VStack(spacing: 6) {
                        Text(authManager.currentUserEmail ?? "")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("\(t("Member since:")) \(formattedCreationDate)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 30)
                    
                    Spacer()
                    
                    // Log Out Button
                    Button(action: {
                        authManager.logout()
                        dismiss()
                    }) {
                        Text(t("Log Out"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    
                    // Change Password Button
                    Button(action: {
                        withAnimation {
                            isChangingPassword = true
                        }
                    }) {
                        Text(t("Change Password"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    
                    // Delete Account Button
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Text(t("Delete Account"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    
                    if let deleteError = deleteError {
                        Text(deleteError)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)
                    }
                    
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 10)
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 400, height: 550) // Adjust height to support three password fields cleanly
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
        .foregroundColor(.white)
        .alert(t("Delete Account"), isPresented: $showDeleteConfirmation) {
            SecureField(t("Password"), text: $deletePassword)
            Button(t("Delete"), role: .destructive) {
                performAccountDeletion()
            }
            Button(t("Cancel"), role: .cancel) {
                deletePassword = ""
            }
        } message: {
            Text(t("Please enter your password to confirm. This action cannot be undone."))
        }
        .onAppear {
            Task {
                await authManager.fetchUserDetails()
            }
        }
    }
    
    private func performPasswordChange() {
        let trimmedOld = oldPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmNewPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedOld.isEmpty {
            changePasswordError = t("Please enter your old password.")
            return
        }
        
        if trimmedNew.isEmpty {
            changePasswordError = t("Password cannot be empty.")
            return
        }
        
        if trimmedNew.count < 6 {
            changePasswordError = t("Password must be at least 6 characters long.")
            return
        }
        
        if trimmedNew != trimmedConfirm {
            changePasswordError = t("Passwords do not match.")
            return
        }
        
        isSavingPassword = true
        changePasswordError = nil
        
        Task {
            do {
                // Verify old password by logging in again
                if let email = authManager.currentUserEmail {
                    try await authManager.login(email: email, password: trimmedOld)
                }
                
                // If login succeeds, update password
                try await authManager.updatePassword(newPassword: trimmedNew)
                
                await MainActor.run {
                    isSavingPassword = false
                    oldPassword = ""
                    newPassword = ""
                    confirmNewPassword = ""
                    withAnimation {
                        showSuccessMessage = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingPassword = false
                    changePasswordError = tError(error.localizedDescription)
                }
            }
        }
    }
    
    private func performAccountDeletion() {
        guard !deletePassword.isEmpty else {
            deleteError = t("Password cannot be empty.")
            return
        }
        
        isDeleting = true
        deleteError = nil
        let passwordToVerify = deletePassword
        
        Task {
            do {
                if let email = authManager.currentUserEmail {
                    try await authManager.login(email: email, password: passwordToVerify)
                }
                
                try await authManager.deleteAccount()
                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = tError(error.localizedDescription)
                }
            }
        }
    }
}

