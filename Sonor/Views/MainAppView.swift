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

struct MainAppView: View {
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
    @State private var isShowingOnboardingSheet = false
    @State private var isShowingThankYouSheet = false
    @State private var isShowingMilestoneSheet = false
    @State private var milestoneHoursForSheet = 10
    
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    
    var body: some View {
        mainContent
    }
    
    // Usunięty thankYouOverlay, bo używamy native .sheet()
    
    @ViewBuilder
    private var mainContent: some View {
        NavigationSplitView {
            // Panel boczny (Sidebar)
            VStack(alignment: .leading, spacing: 0) {
                // Logo aplikacji i tag Beta
                HStack(spacing: 8) {
                    Text("Sonor")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Beta")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(effectiveColorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(effectiveColorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(4)
                }
                .padding(.leading, 10)
                .padding(.trailing, 24)
                .padding(.bottom, 2)
                
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
                
                // Discord Button
                Button(action: {
                    if let url = URL(string: "https://discord.gg/aHAJvAPKf4") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image("discord")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .padding(.leading, 4)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Join Discord"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text(t("Community and Support"))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 88/255, green: 101/255, blue: 242/255))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                
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
                            Text(authManager.isLoggedIn ? t(authManager.accountTier.capitalized) : t("User"))
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
                    } else if networkMonitor.isConnected {
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
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .home:
                            StatisticsView()
                        case .modes:
                            ModesSettingsView(modes: $modes, selectedModeID: $selectedModeID, isShowingSidePanel: $isShowingSidePanel, isPremium: authManager.isLoggedIn && authManager.accountTier == "premium", showLoginSheet: $showLoginSheet)
                        case .dictionary:
                            DictionarySettingsView(showLoginSheet: $showLoginSheet)
                        case .snippets:
                            SnippetsSettingsView(showLoginSheet: $showLoginSheet)
                        case .models:
                            ModelsSettingsView()
                        case .settings:
                            GeneralSettingsView()
                        }
                        Spacer()
                    }
                    .padding(.top, 52)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .ignoresSafeArea(edges: .top)
                
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
                                    .safeGlassEffect(cornerRadius: 8)
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
                                        .safeGlassEffect(cornerRadius: 8)
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
                                        .safeGlassEffect(cornerRadius: 8)
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
                        .safeGlassEffect(cornerRadius: 22)
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
            if !UserDefaults.standard.bool(forKey: "hasSeenOnboardingLocally") {
                isShowingOnboardingSheet = true
            }
            checkTimeSavedMilestones()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowThankYouView"))) { _ in
            isShowingThankYouSheet = true
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
        .sheet(isPresented: $isShowingThankYouSheet) {
            ThankYouView(onComplete: {
                isShowingThankYouSheet = false
            })
            .preferredColorScheme(effectiveColorScheme)
        }
        .sheet(isPresented: $isShowingOnboardingSheet) {
            OnboardingView(onComplete: {
                isShowingOnboardingSheet = false
                // Zapisz lokalnie, że onboarding został obejrzany
                UserDefaults.standard.set(true, forKey: "hasSeenOnboardingLocally")
            }, onLoginRequest: {
                isShowingOnboardingSheet = false
                UserDefaults.standard.set(true, forKey: "hasSeenOnboardingLocally")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showLoginSheet = true
                }
            })
            .preferredColorScheme(effectiveColorScheme)
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .preferredColorScheme(effectiveColorScheme)
                .frame(width: 520)
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
                .preferredColorScheme(effectiveColorScheme)
        }
        .sheet(isPresented: $isShowingMilestoneSheet) {
            TimeSavedMilestoneView(hoursSaved: milestoneHoursForSheet)
                .preferredColorScheme(effectiveColorScheme)
        }
        .background(
            Color.clear
                .sheet(isPresented: $modelManager.showModelsRequiredModal) {
                    ModelsRequiredExplanationView()
                        .preferredColorScheme(effectiveColorScheme)
                }
                .sheet(isPresented: $modelManager.showDownloadErrorModal) {
                    ModelDownloadErrorView(error: modelManager.downloadError ?? t("An unknown network error occurred."))
                        .preferredColorScheme(effectiveColorScheme)
                }
        )
        .onAppear {
            loadModes()
        }
        .overlay(
            IncognitoAnimationOverlay()
                .allowsHitTesting(false)
        )
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
    
    private func checkTimeSavedMilestones() {
        let stats = UserDefaults.standard.data(forKey: "usageStats").flatMap {
            try? JSONDecoder().decode([UsageStat].self, from: $0)
        } ?? []
        
        let totalWords = stats.reduce(0) { $0 + $1.wordCount }
        let totalSpeakingTime = stats.reduce(0) { $0 + $1.duration }
        
        let typingTimeSeconds = (Double(totalWords) / 40.0) * 60.0
        let savedSeconds = max(0.0, typingTimeSeconds - totalSpeakingTime)
        let savedHours = savedSeconds / 3600.0
        
        let thresholds = [10, 50, 100, 200, 500, 1000]
        
        for threshold in thresholds.sorted(by: <) {
            if savedHours >= Double(threshold) {
                let key = "shownMilestone_\\(threshold)h"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    self.milestoneHoursForSheet = threshold
                    self.isShowingMilestoneSheet = true
                    break
                }
            }
        }
    }
}


// Przycisk menu z efektem hover i zaznaczenia


enum RecordingHotkeyType: String {
    case main = "main"
    case cancel = "cancel"
    case pause = "pause"
    case assistant = "assistant"
}













// MARK: - Custom Modals for Models




// MARK: - Premium Feature Explanation Modals






