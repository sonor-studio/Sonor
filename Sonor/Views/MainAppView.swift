import SwiftUI
import CoreGraphics
import ScreenCaptureKit
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
    @State private var isHoveringTrafficLights = false
    @FocusState private var isDummyFocused: Bool
    @ObservedObject private var authManager = AuthManager.shared
    @State private var showLoginSheet = false
    @State private var isShowingProfileSheet = false
    @State private var isProfileCardHovered = false
    @State private var isShowingOnboardingSheet = false
    @State private var isShowingThankYouSheet = false
    @State private var isShowingMilestoneSheet = false
    @State private var isShowingMicPermissionSheet = false
    @State private var isShowingAccessibilityPermissionSheet = false
    @State private var isShowingChangelogSheet = false
    @State private var milestoneHoursForSheet = 10
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    var body: some View {
        mainContent
    }
    @ViewBuilder
    private var mainContent: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarView(
                    selectedTab: $selectedTab,
                    isProfileCardHovered: $isProfileCardHovered,
                    showLoginSheet: $showLoginSheet,
                    isShowingProfileSheet: $isShowingProfileSheet,
                    effectiveColorScheme: effectiveColorScheme
                )
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            HStack(spacing: 0) {
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
                
                if selectedTab == .modes && (authManager.isLoggedIn || modes.first(where: { $0.id.uuidString == selectedModeID })?.name == "Raw Output" || modes.first(where: { $0.id.uuidString == selectedModeID })?.name == "Zwykły output"), modes.firstIndex(where: { $0.id.uuidString == selectedModeID }) != nil {
                    ModeEditorView(modes: $modes, selectedModeID: $selectedModeID)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, idealWidth: 1200, minHeight: 600, idealHeight: 700)
        .preferredColorScheme(effectiveColorScheme)
        .onAppear {
            isDummyFocused = true
            if !UserDefaults.standard.bool(forKey: "hasSeenOnboardingLocally") {
                isShowingOnboardingSheet = true
            }
            checkTimeSavedMilestones()
            
            if !AXIsProcessTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(name: Notification.Name("ShowAccessibilityPermissionView"), object: nil)
                }
            }
            
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let lastSeenVersion = UserDefaults.standard.string(forKey: "lastSeenChangelogVersion") ?? ""
            let hasChangelogFeatures = !ChangelogLocalization.shared.getFeatures().isEmpty
            
            if !lastSeenVersion.isEmpty && lastSeenVersion != currentVersion && hasChangelogFeatures {
                isShowingChangelogSheet = true
                UserDefaults.standard.set(currentVersion, forKey: "lastSeenChangelogVersion")
            } else if lastSeenVersion.isEmpty || (!hasChangelogFeatures && lastSeenVersion != currentVersion) {
                UserDefaults.standard.set(currentVersion, forKey: "lastSeenChangelogVersion")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowThankYouView"))) { _ in
            isShowingThankYouSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowMicPermissionView"))) { _ in
            isShowingAccessibilityPermissionSheet = false
            isShowingMicPermissionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAccessibilityPermissionView"))) { _ in
            isShowingMicPermissionSheet = false
            isShowingAccessibilityPermissionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HidePermissionViews"))) { _ in
            isShowingMicPermissionSheet = false
            isShowingAccessibilityPermissionSheet = false
        }
        .sheet(isPresented: $isShowingThankYouSheet) {
            ThankYouView(onComplete: {
                isShowingThankYouSheet = false
            })
            .preferredColorScheme(effectiveColorScheme)
        }
        .sheet(isPresented: $isShowingChangelogSheet) {
            ChangelogView(onComplete: {
                isShowingChangelogSheet = false
            })
            .preferredColorScheme(effectiveColorScheme)
        }
        .sheet(isPresented: $isShowingMicPermissionSheet) {
            MicrophonePermissionExplanationView()
                .preferredColorScheme(effectiveColorScheme)
        }
        .sheet(isPresented: $isShowingAccessibilityPermissionSheet) {
            AccessibilityPermissionExplanationView()
                .preferredColorScheme(effectiveColorScheme)
        }
        .sheet(isPresented: $isShowingOnboardingSheet) {
            OnboardingView(onComplete: {
                isShowingOnboardingSheet = false
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
            UserDefaults.standard.synchronize()
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





enum RecordingHotkeyType: String {
    case main = "main"
    case cancel = "cancel"
    case pause = "pause"
    case assistant = "assistant"
}

























