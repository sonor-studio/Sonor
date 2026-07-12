import SwiftUI
import Carbon
import AppKit

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) var appColorScheme
    @ObservedObject var localizer = LocalizationManager.shared
    @AppStorage("autoLearnDictionary") private var autoLearnDictionary = false
    @AppStorage("hotkeyString") private var hotkeyString = "Ctrl + Opt + Space"
    @AppStorage("hotkeyString_cancel") private var hotkeyStringCancel = "Ctrl + Opt + Z"
    @AppStorage("hotkeyString_pause") private var hotkeyStringPause = "Ctrl + Opt + X"
    @AppStorage("hotkeyString_assistant") private var hotkeyStringAssistant = "Ctrl + Opt + C"
    @AppStorage("hotkeyMode") private var hotkeyMode: HotkeyMode = .click
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("playAnySound") private var playAnySound = true
    @AppStorage("playSound_Start") private var playSound_Start = true
    @AppStorage("playSound_Error") private var playSound_Error = true
    @AppStorage("playSound_End") private var playSound_End = true
    @ObservedObject private var memoryManager = MessageMemoryManager.shared
    @State private var isShowingSwitchToRamAlert = false
    @State private var isShowingDuplicateShortcutAlert = false
    @State private var activeRecordingType: RecordingHotkeyType? = nil
    @State private var eventMonitor: Any?
    @State private var pressedModifiers: Set<UInt16> = []
    @State private var maxPressedModifiers: Set<UInt16> = []
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
            footerSection
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
            }
        } message: {
            Text(t("Switching to RAM-only means your persistent history file will be deleted and your current history will disappear forever once you close the application. Are you sure you want to continue?"))
        }
        .alert(t("Duplicate Shortcut"), isPresented: $isShowingDuplicateShortcutAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(t("This shortcut is already used by another action."))
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
                    HotkeyManager.shared.startListening()
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
                    HotkeyManager.shared.startListening()
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
    private func clearShortcut(for type: RecordingHotkeyType) {
        let codeKey = type == .main ? "hotkeyCode" : "hotkeyCode_\(type.rawValue)"
        let modKey = type == .main ? "hotkeyModifiers" : "hotkeyModifiers_\(type.rawValue)"
        let strKey = type == .main ? "hotkeyString" : "hotkeyString_\(type.rawValue)"
        
        UserDefaults.standard.set(-1, forKey: codeKey)
        UserDefaults.standard.set(0, forKey: modKey)
        UserDefaults.standard.set("None", forKey: strKey)
        
        HotkeyManager.shared.startListening()
    }

    private func hotkeyRow(title: String, type: RecordingHotkeyType, hotkeyStringVal: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t(title))
                .font(.system(size: 14, weight: .bold))
            HStack(spacing: 8) {
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

                if hotkeyStringVal != "None" {
                    Button(action: {
                        clearShortcut(for: type)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 38, height: 38)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
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
                    Toggle(t("Error / Not recognized / No text field"), isOn: $playSound_Error)
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
    private var footerSection: some View {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        VStack(spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Made by Sonor Studio"))
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(t("Version")) \(appVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Link(destination: URL(string: "https://github.com/sonor-studio/Sonor")!) {
                        Image("github_logo")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.primary)
                    }
                    .help("https://github.com/sonor-studio/Sonor")
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.05))
            
            HStack(alignment: .bottom) {
                Text("© 2026 Sonor Studio. \(t("All rights reserved."))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                
                Spacer()
                
                Text(t("Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 350, alignment: .trailing)
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
                            pressedModifiers.insert(keyCode)
                            maxPressedModifiers.insert(keyCode)
                        } else {
                            pressedModifiers.remove(keyCode)
                            if pressedModifiers.isEmpty && !maxPressedModifiers.isEmpty {
                                let finalKeyCode = keyCode
                                var carbonModifiers: UInt32 = 0
                                var str = ""
                                
                                let otherMods = maxPressedModifiers.subtracting([finalKeyCode])
                                if otherMods.contains(54) || otherMods.contains(55) { carbonModifiers |= UInt32(cmdKey); str += "Cmd + " }
                                if otherMods.contains(56) || otherMods.contains(60) { carbonModifiers |= UInt32(shiftKey); str += "Shift + " }
                                if otherMods.contains(58) || otherMods.contains(61) { carbonModifiers |= UInt32(optionKey); str += "Opt + " }
                                if otherMods.contains(59) || otherMods.contains(62) { carbonModifiers |= UInt32(controlKey); str += "Ctrl + " }
                                
                                switch finalKeyCode {
                                case 54, 55: str += "Command"
                                case 56, 60: str += "Shift"
                                case 58, 61: str += "Option"
                                case 59, 62: str += "Control"
                                case 63: str += "Fn"
                                default: break
                                }
                                
                                if isShortcutInUse(keyCode: Int(finalKeyCode), modifiers: Int(carbonModifiers), ignoringType: recordingType) {
                                    isShowingDuplicateShortcutAlert = true
                                    activeRecordingType = nil
                                    HotkeyManager.shared.startListening()
                                    maxPressedModifiers.removeAll()
                                    return nil
                                }
                                
                                UserDefaults.standard.set(Int(finalKeyCode), forKey: codeKey)
                                UserDefaults.standard.set(Int(carbonModifiers), forKey: modKey)
                                UserDefaults.standard.set(str, forKey: strKey)
                                activeRecordingType = nil
                                HotkeyManager.shared.startListening()
                                maxPressedModifiers.removeAll()
                                return nil 
                            }
                        }
                    }
                    return event
                }
                if event.type == .keyDown {
                    pressedModifiers.removeAll()
                    maxPressedModifiers.removeAll()
                    let keyCode = event.keyCode
                    if keyCode == 53 {
                        activeRecordingType = nil
                        HotkeyManager.shared.startListening() 
                        return nil 
                    }
                    let modifiers = event.modifierFlags
                    let hasModifiers = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control)
                    let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 123, 124, 125, 126]
                    let isFunctionKey = functionKeyCodes.contains(keyCode)
                    if !hasModifiers && !isFunctionKey {
                        return nil 
                    }
                    var carbonModifiers: UInt32 = 0
                    if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
                    if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
                    if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
                    if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
                    
                    if isShortcutInUse(keyCode: Int(keyCode), modifiers: Int(carbonModifiers), ignoringType: recordingType) {
                        isShowingDuplicateShortcutAlert = true
                        activeRecordingType = nil
                        HotkeyManager.shared.startListening()
                        return nil
                    }
                    
                    UserDefaults.standard.set(Int(keyCode), forKey: codeKey)
                    UserDefaults.standard.set(Int(carbonModifiers), forKey: modKey)
                    var str = ""
                    if modifiers.contains(.command) { str += "Cmd + " }
                    if modifiers.contains(.shift) { str += "Shift + " }
                    if modifiers.contains(.option) { str += "Opt + " }
                    if modifiers.contains(.control) { str += "Ctrl + " }
                    let keyString: String
                    switch keyCode {
                    case 49: keyString = "Space"
                    case 53: keyString = "Esc"
                    case 36: keyString = "Return"
                    case 48: keyString = "Tab"
                    case 51: keyString = "Delete"
                    case 117: keyString = "Forward Delete"
                    case 123: keyString = "Left"
                    case 124: keyString = "Right"
                    case 125: keyString = "Down"
                    case 126: keyString = "Up"
                    case 115: keyString = "Home"
                    case 119: keyString = "End"
                    case 116: keyString = "Page Up"
                    case 121: keyString = "Page Down"
                    case 122: keyString = "F1"
                    case 120: keyString = "F2"
                    case 99: keyString = "F3"
                    case 118: keyString = "F4"
                    case 96: keyString = "F5"
                    case 97: keyString = "F6"
                    case 98: keyString = "F7"
                    case 100: keyString = "F8"
                    case 101: keyString = "F9"
                    case 109: keyString = "F10"
                    case 103: keyString = "F11"
                    case 111: keyString = "F12"
                    default:
                        let keyChar = event.charactersIgnoringModifiers?.first ?? "`"
                        keyString = String(keyChar).uppercased()
                    }
                    str += keyString
                    UserDefaults.standard.set(str, forKey: strKey)
                    activeRecordingType = nil
                    HotkeyManager.shared.startListening()
                    return nil 
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
    
    private func isShortcutInUse(keyCode: Int, modifiers: Int, ignoringType: RecordingHotkeyType?) -> Bool {
        let types: [RecordingHotkeyType] = [.main, .cancel, .pause, .assistant]
        for type in types {
            if type == ignoringType { continue }
            let codeKey = type == .main ? "hotkeyCode" : "hotkeyCode_\(type.rawValue)"
            let modKey = type == .main ? "hotkeyModifiers" : "hotkeyModifiers_\(type.rawValue)"
            let strKey = type == .main ? "hotkeyString" : "hotkeyString_\(type.rawValue)"
            
            let existingStr = UserDefaults.standard.string(forKey: strKey) ?? (type == .main ? "Ctrl + Opt + Space" : (type == .cancel ? "Ctrl + Opt + Z" : (type == .pause ? "Ctrl + Opt + X" : "Ctrl + Opt + C")))
            if existingStr == "None" { continue }
            
            let defaultCode = type == .main ? 49 : (type == .cancel ? 6 : (type == .pause ? 7 : 8))
            let defaultMods = 0x1800
            
            let existingCode = UserDefaults.standard.object(forKey: codeKey) as? Int ?? defaultCode
            let existingMods = UserDefaults.standard.object(forKey: modKey) as? Int ?? defaultMods
            
            if existingCode == keyCode && existingMods == modifiers {
                return true
            }
        }
        return false
    }
}
