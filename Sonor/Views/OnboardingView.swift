import SwiftUI
import Carbon

struct OnboardingView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var currentPage = 0
    let onComplete: () -> Void
    var onLoginRequest: (() -> Void)? = nil
    @AppStorage("hotkeyMode") private var hotkeyMode: HotkeyMode = .click
    @AppStorage("hotkeyString") private var hotkeyString = "Cmd + Shift + `"
    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any? = nil
    @State private var lastModifierPressed: UInt16? = nil
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                if !isRecordingHotkey {
                    withAnimation {
                        if currentPage < 4 {
                            currentPage += 1
                        } else {
                            if let login = onLoginRequest {
                                login()
                            } else {
                                onComplete()
                            }
                        }
                    }
                }
            }) {
                EmptyView()
            }
            .keyboardShortcut(.defaultAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            Spacer()
                .frame(height: 20)
            ZStack {
                if currentPage == 0 {
                    onboardingSlideCustomIcon(
                        title: t("Welcome to Sonor"),
                        iconView: AnyView(
                            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                        ),
                        description: t("You are now part of an exclusive group of users with access to a highly advanced voice assistant on the market. Sonor is designed for local reliability and a luxurious experience."),
                        features: [
                            (icon: "crown.fill", title: t("Premium Experience"), description: t("A meticulously designed interface where elegance and supreme usability are the priorities.")),
                            (icon: "command.square.fill", title: t("Total Freedom"), description: t("You can use dictation and the assistant absolutely anywhere, regardless of what application you are using on your Mac."))
                        ]
                    ).transition(.opacity)
                } else if currentPage == 1 {
                    onboardingSlide(
                        title: t("Absolute Privacy"),
                        icon: "lock.shield.fill",
                        description: t("Your data is completely yours. Sonor uses an architecture where every piece of information stays on your device. No cloud, no telemetry, no compromises."),
                        features: [
                            (icon: "network.slash", title: t("100% Offline Processing"), description: t("Voice recognition and AI tasks are performed locally, entirely without internet access.")),
                            (icon: "memorychip", title: t("Volatile Memory"), description: t("Your voice is processed in volatile memory and destroyed immediately after the operation completes."))
                        ]
                    ).transition(.opacity)
                } else if currentPage == 2 {
                    onboardingSlide(
                        title: t("Full Transparency"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        description: t("Trust is built on transparency. Sonor is fully open-source, allowing you and the community to audit every line of code to ensure the privacy promises are absolutely certain."),
                        features: [
                            (icon: "doc.text.magnifyingglass", title: t("Auditable Code"), description: t("Every algorithmic decision and data flow is public. You can thoroughly verify how it works under the hood.")),
                            (icon: "building.columns.fill", title: t("Community Driven"), description: t("Developed with the highest engineering standards and the support of independent experts."))
                        ]
                    ).transition(.opacity)
                } else if currentPage == 3 {
                    configurationSlide()
                        .transition(.opacity)
                } else if currentPage == 4 {
                    loginSlide()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: currentPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 16) {
                if currentPage > 0 {
                    Button(action: {
                        withAnimation {
                            currentPage -= 1
                        }
                    }) {
                        Text(t("Previous"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 110)
                            .padding(.vertical, 12)
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                } else {
                    Spacer().frame(width: 110)
                }
                Spacer()
                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? (colorScheme == .dark ? Color.white : Color.black) : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentPage == index ? 1.2 : 1.0)
                            .onTapGesture {
                                withAnimation {
                                    currentPage = index
                                }
                            }
                    }
                }
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if currentPage < 4 {
                            currentPage += 1
                        } else {
                            onComplete()
                        }
                    }
                }) {
                    Text(currentPage < 4 ? t("Next") : t("Continue without account"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(currentPage < 4 ? (colorScheme == .dark ? .black : .white) : (colorScheme == .dark ? .white : .black))
                        .frame(width: currentPage < 4 ? 110 : 200)
                        .padding(.vertical, 12)
                        .background(currentPage < 4 ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .padding(.top, 16)
        }
        .frame(width: 580, height: 500)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onDisappear {
            removeEventMonitor()
        }
    }
    @ViewBuilder
    private func onboardingSlide(title: String, icon: String, description: String, features: [(icon: String, title: String, description: String)]) -> some View {
        onboardingSlideCustomIcon(
            title: title,
            iconView: AnyView(
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            ),
            description: description,
            features: features
        )
    }

    @ViewBuilder
    private func onboardingSlideCustomIcon(title: String, iconView: AnyView, description: String, features: [(icon: String, title: String, description: String)]) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                iconView
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 16)
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(features, id: \.title) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            Text(feature.description)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 10)
    }
    @ViewBuilder
    private func configurationSlide() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Configure Sonor"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 16)
            Text(t("Choose how you want to use the assistant. You can always change this later in settings."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("Operation mode"))
                        .font(.system(size: 14, weight: .bold))
                    HStack(spacing: 15) {
                        Button(action: {
                            withAnimation(.spring()) {
                                hotkeyMode = .click
                            }
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "hand.point.up.fill")
                                    .font(.system(size: 18))
                                Text(t("On click"))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(hotkeyMode == .click ? (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)) : Color.clear)
                            .cornerRadius(10)
                            .contentShape(Rectangle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(hotkeyMode == .click ? (colorScheme == .dark ? Color.white : Color.black) : Color.secondary.opacity(0.3), lineWidth: hotkeyMode == .click ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        Button(action: {
                            withAnimation(.spring()) {
                                hotkeyMode = .hold
                            }
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 18))
                                Text(t("On hold"))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(hotkeyMode == .hold ? (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)) : Color.clear)
                            .cornerRadius(10)
                            .contentShape(Rectangle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(hotkeyMode == .hold ? (colorScheme == .dark ? Color.white : Color.black) : Color.secondary.opacity(0.3), lineWidth: hotkeyMode == .hold ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("Main shortcut (Start/Stop)"))
                        .font(.system(size: 14, weight: .bold))
                    Button(action: {
                        if isRecordingHotkey {
                            isRecordingHotkey = false
                            removeEventMonitor()
                            HotkeyManager.shared.startListening()
                        } else {
                            isRecordingHotkey = true
                            HotkeyManager.shared.stopListening()
                            setupEventMonitor()
                        }
                    }) {
                        HStack {
                            Text(isRecordingHotkey ? t("Press shortcut...") : hotkeyString)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isRecordingHotkey ? (colorScheme == .dark ? .black : .white) : .primary)
                            Spacer()
                            Image(systemName: "keyboard")
                                .font(.system(size: 16))
                                .foregroundColor(isRecordingHotkey ? (colorScheme == .dark ? .black : .white) : .secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(isRecordingHotkey ? (colorScheme == .dark ? .white : .black) : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isRecordingHotkey ? (colorScheme == .dark ? .white : .black) : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 10)
    }
    @ViewBuilder
    private func loginSlide() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Unlock full potential"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 12)
            Text(t("Creating a free account unlocks access to advanced assistant features. You can always do this later in settings."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 16) {
                let features = [
                    (icon: "brain.head.profile", title: t("Zaawansowane modele LLM"), description: t("Intelligent formatting, analysis, and processing of your notes and commands.")),
                    (icon: "text.badge.plus", title: t("Szablony i Snippety"), description: t("Save your most frequently used message templates and insert them in a blink of an eye.")),
                    (icon: "text.book.closed.fill", title: t("Osobisty Słownik"), description: t("The application learns your specific vocabulary and proper names every day."))
                ]
                ForEach(features, id: \.title) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            Text(feature.description)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
            Button(action: {
                if let login = onLoginRequest {
                    login()
                } else {
                    onComplete()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.open.fill")
                    Text(t("Log in for free"))
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(colorScheme == .dark ? Color.white : Color.black)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.horizontal, 60)
            Spacer()
        }
        .padding(.top, 10)
    }
    private func setupEventMonitor() {
        removeEventMonitor()
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
                                hotkeyString = str
                                isRecordingHotkey = false
                                removeEventMonitor()
                                HotkeyManager.shared.startListening()
                                lastModifierPressed = nil
                                return nil
                            }
                            lastModifierPressed = nil
                        }
                    }
                    return event
                }
                if event.type == .keyDown {
                    lastModifierPressed = nil
                    let keyCode = event.keyCode
                    if keyCode == 53 { 
                        isRecordingHotkey = false
                        removeEventMonitor()
                        HotkeyManager.shared.startListening()
                        return nil
                    }
                    let modifiers = event.modifierFlags
                    let hasModifiers = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control)
                    let functionKeyCodes: Set<UInt16> = [53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 123, 124, 125, 126, 49]
                    let isFunctionKey = functionKeyCodes.contains(keyCode)
                    if !hasModifiers && !isFunctionKey {
                        return event
                    }
                    var carbonModifiers: UInt32 = 0
                    if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
                    if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
                    if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
                    if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
                    UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyCode")
                    UserDefaults.standard.set(Int(carbonModifiers), forKey: "hotkeyModifiers")
                    var str = ""
                    if modifiers.contains(.command) { str += "Cmd + " }
                    if modifiers.contains(.shift) { str += "Shift + " }
                    if modifiers.contains(.option) { str += "Opt + " }
                    if modifiers.contains(.control) { str += "Ctrl + " }
                    let keyChar = event.charactersIgnoringModifiers?.first ?? "`"
                    str += String(keyChar).uppercased()
                    UserDefaults.standard.set(str, forKey: "hotkeyString")
                    hotkeyString = str
                    isRecordingHotkey = false
                    removeEventMonitor()
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
}
