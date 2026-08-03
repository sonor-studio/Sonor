import SwiftUI
import Combine

struct NotchShape: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topRadius: CGFloat = 14 // Wklęsły łuk u samej góry
        let padding: CGFloat = topRadius // Odległość od krawędzi ramki
        
        // Start from top-left ceiling
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Lewe, wklęsłe połączenie (sufit -> ściana)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + padding, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + padding, y: rect.minY)
        )
        
        // Lewa pionowa ściana w dół do zakrętu dolnego
        path.addLine(to: CGPoint(x: rect.minX + padding, y: rect.maxY - cornerRadius))
        
        // Lewy, dolny wypukły róg
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + padding + cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + padding, y: rect.maxY)
        )
        
        // Dolna, horyzontalna krawędź
        path.addLine(to: CGPoint(x: rect.maxX - padding - cornerRadius, y: rect.maxY))
        
        // Prawy, dolny wypukły róg
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - padding, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.maxX - padding, y: rect.maxY)
        )
        
        // Prawa pionowa ściana w górę do sufitu
        path.addLine(to: CGPoint(x: rect.maxX - padding, y: rect.minY + topRadius))
        
        // Prawe, wklęsłe połączenie (ściana -> sufit)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - padding, y: rect.minY)
        )
        
        // Zamknięcie maski na suficie
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        
        return path
    }
}

struct NotchHUDView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var modelManager = ModelManager.shared
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("hudPositionMode") private var hudPositionMode: HUDPositionMode = .notch
    
    @State private var showList = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var hoveredModeID: UUID? = nil
    
    // Notification states
    @State private var isUndone = false
    @State private var dictProgress: CGFloat = 1.0
    @State private var isCopied = false
    
    // Animation states
    @State private var animatedWidth: CGFloat = 188
    @State private var isExpanded: Bool = false
    
    private let showNotification = NotificationCenter.default.publisher(for: NSNotification.Name("HUDWindowDidShow"))
    private let hideNotification = NotificationCenter.default.publisher(for: NSNotification.Name("HUDWindowWillHide"))
    
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
    
    private var isInitializing: Bool {
        return controller.statusText == "Initializing"
    }
    
    private var isFinalState: Bool {
        let text = controller.statusText
        return text == "Cancelled" || text == "Done!" || text == "No text recognized." || text == "Error: Missing model" || text == "No microphone permission" || text == "Microphone error"
    }
    
    private var currentTargetHeight: CGFloat {
        if controller.activeDictionaryNotification != nil || controller.activeCopyNotification != nil {
            return 96
        } else if !isInitializing && !isFinalState && controller.isRecording {
            let displayedCount = min(controller.availableModes.count, 5)
            let listHeight = CGFloat(displayedCount * 28)
            return showList ? (92 + listHeight) : 96
        } else {
            return 44
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var loaderView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .colorScheme(.dark)
            Text(NSLocalizedString(controller.statusText, comment: ""))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
    
    private var audioWavesView: some View {
        let barCount = 12
        let levels = Array(controller.audioLevels.suffix(barCount))
        return HStack(spacing: 2) {
            ForEach(0..<levels.count, id: \.self) { index in
                let level = levels[index]
                let barHeight = CGFloat(2 + (level * 250))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(controller.isPaused ? Color.white.opacity(0.4) : Color.white)
                    .frame(width: 3, height: min(barHeight, 24))
                    .animation(.spring(response: 0.1, dampingFraction: 0.5), value: level)
            }
        }
        .frame(height: 24)
    }
    
    private var assistantSelector: some View {
        Button(action: {
            withAnimation { showList.toggle() }
        }) {
            HStack {
                ZStack(alignment: .leading) {
                    Text(t(controller.currentMode?.name ?? "Wybierz tryb"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .id(controller.currentMode?.id ?? UUID())
                }
                Spacer()
                Image(systemName: showList ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
            .background(Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(NoAnimButtonStyle())
        .focusable(false)
    }
    
    private var dropdownListView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(controller.availableModes) { mode in
                    Button(action: {
                        controller.selectMode(mode)
                        withAnimation { showList = false }
                    }) {
                        HStack {
                            Text(t(mode.name))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            if controller.currentMode?.id == mode.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            controller.currentMode?.id == mode.id ? Color.white.opacity(0.2) :
                            (hoveredModeID == mode.id ? Color.white.opacity(0.1) : Color.clear)
                        )
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                hoveredModeID = mode.id
                            } else if hoveredModeID == mode.id {
                                hoveredModeID = nil
                            }
                        }
                    }
                    .buttonStyle(NoAnimButtonStyle())
                    .focusable(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: CGFloat(5 * 28))
        .background(Color.clear)
        .cornerRadius(4)
        .padding(.bottom, 8)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Skompresowany widok do animacji, clipping go maskuje by ladnie wyszedł ze srodka
            VStack(spacing: 0) {
                // Główny panel Notch'a (Nagrywanie i Inicjalizacja)
                HStack(spacing: 12) {
                    // Lewa strona: Animacja audio i timer lub Przetwarzanie
                    HStack(spacing: 8) {
                        if !controller.isRecording && !isInitializing && controller.activeDictionaryNotification == nil && controller.activeCopyNotification == nil {
                            loaderView
                        } else {
                            audioWavesView
                            Text(formatDuration(recordingDuration))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    // Prawa strona: Przyciski sterujące
                    HStack(spacing: 8) {
                        if controller.canRetryTranscription {
                            Button(action: {
                                controller.retryTranscription()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Button(action: {
                            controller.togglePause()
                        }) {
                            Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            controller.cancelRecording()
                            WindowManager.shared.hideHUD()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(width: 120, alignment: .trailing)
                    .opacity(isInitializing || (!controller.isRecording && !isFinalState) ? 0 : 1)
                }
                .padding(.horizontal, 32)
                .frame(width: 508, height: 44)
                
                // Selector asystenta lub Powiadomienia (pod głównym paskiem)
                if controller.activeDictionaryNotification != nil || controller.activeCopyNotification != nil {
                    VStack(spacing: 8) {
                        Divider().background(Color.white.opacity(0.2))
                            .padding(.horizontal, 32)
                        
                        if let _ = controller.activeDictionaryNotification {
                            dictionaryNotificationView
                        } else if let _ = controller.activeCopyNotification {
                            copyNotificationView
                        }
                    }
                    .padding(.bottom, 8)
                } else if !isInitializing && !isFinalState && controller.isRecording {
                    VStack(spacing: 8) {
                        Divider().background(Color.white.opacity(0.2))
                            .padding(.horizontal, 32)
                        
                        assistantSelector
                            .padding(.horizontal, 32)
                            .padding(.bottom, showList ? 0 : 8)
                        
                        if showList {
                            dropdownListView
                                .padding(.horizontal, 32)
                        }
                    }
                }
            }
            .frame(width: 508, height: currentTargetHeight, alignment: .top)
            .frame(width: animatedWidth, height: isExpanded ? currentTargetHeight : 0, alignment: .top) // clipping bounds
            .background(Color(nsColor: .black))
            .mask(NotchShape(cornerRadius: 16))
            
            Spacer()
        }
        .frame(width: 600, height: 600, alignment: .top)
        .onAppear {
            triggerOpenAnimation()
        }
        .onReceive(showNotification) { _ in
            triggerOpenAnimation()
        }
        .onReceive(hideNotification) { _ in
            triggerCloseAnimation()
        }
        .task(id: controller.isRecording) {
            if controller.isRecording {
                recordingDuration = 0
                while !Task.isCancelled && controller.isRecording {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !controller.isPaused && controller.statusText != "Initializing" {
                        recordingDuration += 1
                    }
                }
            }
        }
        .onChange(of: hudPositionMode) { newMode in
            WindowManager.shared.updateHUDPosition(for: newMode)
        }
    }
    
    private func triggerOpenAnimation() {
        animatedWidth = 188
        isExpanded = false
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if hudPositionMode == .notch {
                animatedWidth = 508
            }
            isExpanded = true
        }
    }
    
    private func triggerCloseAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            if hudPositionMode == .notch {
                animatedWidth = 188
                isExpanded = false
            }
        }
    }
    
    // MARK: - Notifications
    
    private var dictionaryNotificationView: some View {
        guard let notification = controller.activeDictionaryNotification else { return AnyView(EmptyView()) }
        return AnyView(
            ZStack(alignment: .bottomLeading) {
                Button(action: {}) { Color.white.opacity(0.001) }
                    .buttonStyle(PlainButtonStyle())
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.leading, 12)
                    Text("\"\(notification.wrong)\" ➔ \"\(notification.correct)\"")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isUndone = true
                        }
                        controller.undoDictionaryEntry(delayHide: true)
                    }) {
                        ZStack {
                            if isUndone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            } else {
                                Text(NSLocalizedString("Undo", comment: ""))
                                    .font(.system(size: 11, weight: .bold))
                                    .fixedSize()
                            }
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, isUndone ? 0 : 10)
                        .frame(width: isUndone ? 24 : nil, height: 24)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                    .padding(.trailing, 8)
                }
                .frame(width: 284, height: 40)
                
                Capsule()
                    .fill(Color.white)
                    .frame(width: 284 * dictProgress, height: 4)
                    .opacity(isUndone ? 0 : 1)
            }
            .frame(width: 284, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.15))
            )
            .onAppear {
                isUndone = false
                dictProgress = 1.0
                withAnimation(.linear(duration: 5.0)) {
                    dictProgress = 0.0
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        )
    }
    
    private var copyNotificationView: some View {
        guard let _ = controller.activeCopyNotification else { return AnyView(EmptyView()) }
        return AnyView(
            ZStack(alignment: .bottomLeading) {
                Button(action: {}) { Color.white.opacity(0.001) }
                    .buttonStyle(PlainButtonStyle())
                HStack(spacing: 8) {
                    Text(NSLocalizedString("Field not detected", comment: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.leading, 14)
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isCopied = true
                        }
                        controller.copyNotificationTextToClipboard(delayHide: true)
                    }) {
                        ZStack {
                            if isCopied {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            } else {
                                Text(NSLocalizedString("Copy", comment: ""))
                                    .font(.system(size: 11, weight: .bold))
                                    .fixedSize()
                            }
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, isCopied ? 0 : 10)
                        .frame(width: isCopied ? 24 : nil, height: 24)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                    .padding(.trailing, 8)
                }
                .frame(width: 284, height: 40)
            }
            .frame(width: 284, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.15))
            )
            .onAppear {
                isCopied = false
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        )
    }
}
