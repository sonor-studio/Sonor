import SwiftUI
import Carbon
import AppKit

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) var appColorScheme
    @ObservedObject var localizer = LocalizationManager.shared
    @AppStorage("autoLearnDictionary") private var autoLearnDictionary = false
    @AppStorage("hotkeyString") private var hotkeyString = "Cmd + Shift + `"
    @AppStorage("hotkeyString_cancel") private var hotkeyStringCancel = "None"
    @AppStorage("hotkeyString_pause") private var hotkeyStringPause = "None"
    @AppStorage("hotkeyString_assistant") private var hotkeyStringAssistant = "None"
    @AppStorage("hotkeyMode") private var hotkeyMode: HotkeyMode = .click
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("playAnySound") private var playAnySound = true
    @AppStorage("playSound_Start") private var playSound_Start = true
    @AppStorage("playSound_Error") private var playSound_Error = true
    @AppStorage("playSound_End") private var playSound_End = true
    
    @ObservedObject private var memoryManager = MessageMemoryManager.shared
    @State private var isShowingSwitchToRamAlert = false
    
    @State private var activeRecordingType: RecordingHotkeyType? = nil
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
            historyStorageSection
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
        .alert(t("Critical Warning"), isPresented: $isShowingSwitchToRamAlert) {
            Button(t("Proceed to RAM"), role: .destructive) {
                withAnimation {
                    MessageMemoryManager.shared.switchToRAMMode()
                }
            }
            Button(t("Keep File Storage"), role: .cancel) {
                // Do nothing
            }
        } message: {
            Text(t("Switching to RAM-only means your persistent history file will be deleted and your current history will disappear forever once you close the application. Are you sure you want to continue?"))
        }
    }
    
    @ViewBuilder
    private var historyStorageSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("History Storage Option"))
                .font(.system(size: 16, weight: .semibold))
            
            HStack(spacing: 15) {
                Button(action: {
                    let current = MessageMemoryManager.shared.historyStorageType
                    if current == "File" {
                        isShowingSwitchToRamAlert = true
                    }
                }) {
                    VStack(spacing: 10) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 20))
                        Text(t("RAM-only (Temporary)"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(memoryManager.historyStorageType == "RAM" ? Color.primary.opacity(0.1) : Color.clear)
                    .cornerRadius(10)
                    .contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(memoryManager.historyStorageType == "RAM" ? Color.primary : Color.primary.opacity(0.2), lineWidth: memoryManager.historyStorageType == "RAM" ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    let current = MessageMemoryManager.shared.historyStorageType
                    if current == "RAM" {
                        withAnimation {
                            MessageMemoryManager.shared.switchToFileMode()
                        }
                    }
                }) {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 20))
                        Text(t("Local File (Persistent)"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(memoryManager.historyStorageType == "File" ? Color.primary.opacity(0.1) : Color.clear)
                    .cornerRadius(10)
                    .contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(memoryManager.historyStorageType == "File" ? Color.primary : Color.primary.opacity(0.2), lineWidth: memoryManager.historyStorageType == "File" ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Text(t("Choose whether history is stored safely in temporary RAM or written offline to a local text file that persists between app launches."))
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
    private var keyboardShortcutSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("Keyboard Shortcut"))
                .font(.system(size: 16, weight: .semibold))
            
            HStack(spacing: 15) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        hotkeyMode = .click
                    }
                }) {
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
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        hotkeyMode = .hold
                    }
                }) {
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
                hotkeyRow(title: "Start/Stop Recording", type: .main, hotkeyStringVal: hotkeyString)
                
                hotkeyRow(title: "Cancel Recording", type: .cancel, hotkeyStringVal: hotkeyStringCancel)
                
                if hotkeyMode == .click {
                    hotkeyRow(title: "Pause/Resume", type: .pause, hotkeyStringVal: hotkeyStringPause)
                        .transition(.opacity.combined(with: .offset(y: -10)))
                }
                
                hotkeyRow(title: "Change Assistant", type: .assistant, hotkeyStringVal: hotkeyStringAssistant)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hotkeyMode)
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
    
    private func hotkeyRow(title: String, type: RecordingHotkeyType, hotkeyStringVal: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t(title))
                .font(.system(size: 14, weight: .bold))
            
            Button(action: {
                if activeRecordingType == type {
                    activeRecordingType = nil
                    HotkeyManager.shared.startListening()
                } else {
                    activeRecordingType = type
                    HotkeyManager.shared.stopListening()
                }
            }) {
                let isDark = appColorScheme == .dark
                let isRecording = activeRecordingType == type
                HStack {
                    Text(isRecording ? t("Press keys...") : hotkeyStringVal)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isRecording ? (isDark ? .black : .white) : .primary)
                    Spacer()
                    Image(systemName: "keyboard")
                        .font(.system(size: 16))
                        .foregroundColor(isRecording ? (isDark ? .black : .white) : .secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 15)
                .background(isRecording ? (isDark ? .white : .black) : Color.primary.opacity(0.05))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isRecording ? (isDark ? .white : .black) : Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
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
            if let recordingType = activeRecordingType {
                let codeKey = recordingType == .main ? "hotkeyCode" : "hotkeyCode_\(recordingType.rawValue)"
                let modKey = recordingType == .main ? "hotkeyModifiers" : "hotkeyModifiers_\(recordingType.rawValue)"
                let strKey = recordingType == .main ? "hotkeyString" : "hotkeyString_\(recordingType.rawValue)"
                
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
                                
                                UserDefaults.standard.set(Int(keyCode), forKey: codeKey)
                                UserDefaults.standard.set(0, forKey: modKey)
                                UserDefaults.standard.set(str, forKey: strKey)
                                
                                activeRecordingType = nil
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
                        activeRecordingType = nil
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
                    UserDefaults.standard.set(Int(keyCode), forKey: codeKey)
                    UserDefaults.standard.set(Int(carbonModifiers), forKey: modKey)
                    
                    // Update string representation
                    var str = ""
                    if modifiers.contains(.command) { str += "Cmd + " }
                    if modifiers.contains(.shift) { str += "Shift + " }
                    if modifiers.contains(.option) { str += "Opt + " }
                    if modifiers.contains(.control) { str += "Ctrl + " }
                    
                    let keyChar = event.charactersIgnoringModifiers?.first ?? "`"
                    str += String(keyChar).uppercased()
                    
                    UserDefaults.standard.set(str, forKey: strKey)
                    
                    activeRecordingType = nil
                    
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
