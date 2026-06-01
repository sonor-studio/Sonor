import SwiftUI
import Combine

struct CapsuleHUDView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var modelManager = ModelManager.shared
    
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
    
    private var isInitializing: Bool {
        return controller.statusText == "Initializing"
    }
    
    private var isFinalState: Bool {
        let text = controller.statusText
        return text == "Cancelled" || text == "Done!" || text == "No text recognized." || text == "Error: Missing model" || text == "No microphone permission" || text == "Microphone error"
    }
    
    private var targetWidth: CGFloat {
        if isInitializing || isFinalState {
            return 284.0
        } else if controller.isRecording && controller.activeHotkeyMode == .click {
            return 180.0
        } else {
            return 232.0
        }
    }
    
    // Stan animacji
    @State private var showPauseButton = false
    @State private var width: CGFloat = 180
    @State private var height: CGFloat = 40
    @State private var isProcessing = false
    @State private var opacity: Double = 0
    
    // Stan listy asystentów
    @State private var showList = false
    @State private var hoveredModeID: UUID? = nil
    
    // Stan przeciągania
    @State private var dragTracker = WindowDragTracker()
    
    // Timer i czas trwania nagrywania
    @State private var recordingDuration: TimeInterval = 0
    private let recordingTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    // Podwidoki do odciążenia kompilatora i zapobieżenia timeoutom type-checkingu
    private var assistantSelector: some View {
        Button(action: {
            if !dragTracker.isDragging { withAnimation { showList.toggle() } }
        }) {
            HStack {
                Text(t(controller.currentMode?.name ?? "Wybierz tryb"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: showList ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.primary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .frame(width: 284, height: 40)
            .contentShape(Rectangle())
            .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .simultaneousGesture(dragGesture)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var audioWavesView: some View {
        let barCount = width > 200 ? 31 : 21
        let levels = Array(controller.audioLevels.suffix(barCount))
        return HStack(spacing: 0) {
            Spacer()
                .frame(width: 14)
            
            HStack(spacing: 2) {
                ForEach(0..<levels.count, id: \.self) { index in
                    let level = levels[index]
                    let barHeight = CGFloat(2 + (level * 350))
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(controller.isPaused ? Color.primary.opacity(0.4) : Color.primary)
                        .frame(width: 3, height: min(barHeight, 28))
                        .animation(.spring(response: 0.1, dampingFraction: 0.5), value: level)
                }
            }
            
            Spacer()
                .frame(width: 14)
            
            if controller.isRecording {
                Text(formatDuration(recordingDuration))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            Spacer()
                .frame(width: 12)
        }
        .frame(width: width, height: 40)
        .clipShape(Capsule())
    }
    
    private var loaderView: some View {
        HStack(spacing: 8) {
            Text(t(controller.statusText))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .id(controller.statusText)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            
            Spacer()
            
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let angle = time.truncatingRemainder(dividingBy: 1.0) * 360.0
                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 16, height: 16)
                    .rotationEffect(Angle(degrees: angle))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: 40)
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
                                .foregroundColor(.primary)
                            Spacer()
                            if controller.currentMode?.id == mode.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            controller.currentMode?.id == mode.id ? Color.primary.opacity(0.2) :
                            (hoveredModeID == mode.id ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                hoveredModeID = mode.id
                            } else if hoveredModeID == mode.id {
                                hoveredModeID = nil
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(4)
            }
        }
        .frame(width: 284)
        .frame(height: min(CGFloat(controller.availableModes.count) * 30 + 8, 200))
        .glass(cornerRadius: 12, opacity: 0.7, colorScheme: effectiveColorScheme)
        .transition(.asymmetric(
            insertion: .offset(y: 10).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    private var dictionaryNotificationView: some View {
        guard let notification = controller.activeDictionaryNotification else { return AnyView(EmptyView()) }
        
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.8))
                    .padding(.leading, 12)
                
                Text("\"\(notification.wrong)\" ➔ \"\(notification.correct)\"")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        controller.undoDictionaryEntry()
                    }
                }) {
                    Text(t("Undo"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(effectiveColorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.trailing, 8)
            }
            .frame(width: 284, height: 40)
            .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        )
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Lista asystentów
            if showList {
                dropdownListView
            }
            
            // Główna zawartość (Dół)
            VStack(spacing: 8) {
                if let _ = controller.activeDictionaryNotification {
                    dictionaryNotificationView
                } else {
                    // Pole wyboru asystenta
                    if AuthManager.shared.isLoggedIn && modelManager.gemmaState == .downloaded {
                        if !isInitializing && !isFinalState && controller.isRecording {
                            assistantSelector
                                .transition(.asymmetric(insertion: .offset(y: 40).combined(with: .scale(scale: 0.1)).combined(with: .opacity), removal: .offset(y: 40).combined(with: .scale(scale: 0.1)).combined(with: .opacity)))
                                .zIndex(0)
                        }
                    }
                    
                    // Dolny pasek: Fale/Loader + Przycisk Pauza + Przycisk X
                    HStack(spacing: (isInitializing || isFinalState) ? -40 : 12) {
                        Button(action: {
                            // Puste, żeby przechwycić zdarzenia i nie przerywać dragGesture przez animację
                        }) {
                            ZStack {
                                if !isProcessing && controller.statusText != "Initializing" {
                                    audioWavesView
                                        .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity), removal: .scale(scale: 0.5).combined(with: .opacity)))
                                } else {
                                    loaderView
                                        .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity), removal: .scale(scale: 0.5).combined(with: .opacity)))
                                }
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3), value: isProcessing)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3), value: controller.statusText)
                            .frame(width: width, height: height)
                            .contentShape(Capsule())
                            .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .simultaneousGesture(dragGesture)
                        .zIndex(1)
                        
                        // Przycisk Pauza / Wznów
                        if showPauseButton && !isInitializing && !isFinalState {
                            Button(action: {
                                if !dragTracker.isDragging { controller.togglePause() }
                            }) {
                                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                                    .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .simultaneousGesture(dragGesture)
                            .transition(.asymmetric(insertion: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity), removal: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity)))
                            .zIndex(0)
                        }
                        
                        // Przycisk X (Anuluj)
                        if !isInitializing && !isFinalState {
                            Button(action: {
                                if !dragTracker.isDragging { controller.cancelRecording() }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                                    .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .simultaneousGesture(dragGesture)
                            .transition(.asymmetric(insertion: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity), removal: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity)))
                            .zIndex(0)
                        }
                    }
                }
            }
        }
        .frame(width: 350, height: 600, alignment: .bottom)
        .opacity(opacity)
        .colorScheme(effectiveColorScheme)
        .onAppear {
            controller.reloadModes()
            showPauseButton = controller.activeHotkeyMode == .click && controller.isRecording
            width = targetWidth
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                opacity = 1.0
            }
        }
        .onChange(of: controller.isRecording) { isRecording in
            if !isRecording {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3)) {
                    showPauseButton = false
                    width = targetWidth
                    height = 40
                    isProcessing = true
                }
            } else {
                recordingDuration = 0
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3)) {
                    showPauseButton = controller.activeHotkeyMode == .click
                    width = targetWidth
                    height = 40
                    isProcessing = controller.statusText != "Listening..."
                }
            }
        }
        .onChange(of: controller.statusText) { status in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3)) {
                width = targetWidth
                isProcessing = status != "Listening..."
            }
            if isFinalState {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    opacity = 0.0
                }
                showList = false
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    opacity = 1.0
                }
                showList = false
            }
        }
        .onChange(of: controller.activeDictionaryNotification) { notification in
            if notification == nil && !controller.isRecording {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    opacity = 0.0
                }
                showList = false
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    opacity = 1.0
                }
            }
        }
        .onReceive(recordingTimer) { _ in
            if controller.isRecording && !controller.isPaused && controller.statusText != "Initializing" {
                recordingDuration += 1
            }
        }
    }
    
    // Gest przeciągania
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let currentMouse = NSEvent.mouseLocation
                guard let window = controller.hudWindow else { return }
                
                if dragTracker.startMouseLocation == nil {
                    dragTracker.startMouseLocation = currentMouse
                    dragTracker.startWindowOrigin = window.frame.origin
                    dragTracker.isDragging = true
                }
                
                guard let startMouse = dragTracker.startMouseLocation,
                      let startOrigin = dragTracker.startWindowOrigin else { return }
                
                let deltaX = currentMouse.x - startMouse.x
                let deltaY = currentMouse.y - startMouse.y
                
                var newX = startOrigin.x + deltaX
                var newY = startOrigin.y + deltaY
                
                if let screen = window.screen ?? NSScreen.main {
                    // Używamy visibleFrame, aby respektować pozycję Docka oraz Paska Menu
                    let screenFrame = screen.visibleFrame
                    
                    // Nakładka ma szerokość 350, ale widoczne elementy mają 284 i są wyśrodkowane.
                    // Przez to z lewej i prawej strony mamy po 33 punkty przezroczystego marginesu.
                    let leftMargin: CGFloat = 33
                    let rightMargin: CGFloat = 350 - leftMargin // 317
                    
                    let minXBound = screenFrame.minX - leftMargin
                    let maxXBound = screenFrame.maxX - rightMargin
                    
                    // Widoczna wysokość zależy od tego, czy lista asystentów jest otwarta
                    let visibleHeight = showList ? CGFloat(296) : CGFloat(88)
                    let minYBound = screenFrame.minY
                    let maxYBound = screenFrame.maxY - visibleHeight
                    
                    // Blokada wyjścia poza ekran
                    newX = max(minXBound, min(newX, maxXBound))
                    newY = max(minYBound, min(newY, maxYBound))
                }
                
                window.setFrameOrigin(NSPoint(x: newX, y: newY))
            }
            .onEnded { _ in
                if let window = controller.hudWindow {
                    let origin = window.frame.origin
                    UserDefaults.standard.set(origin.x, forKey: "hudWindowX")
                    UserDefaults.standard.set(origin.y, forKey: "hudWindowY")
                }
                dragTracker.startMouseLocation = nil
                dragTracker.startWindowOrigin = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dragTracker.isDragging = false
                }
            }
    }
}

struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double = 0.5
    var colorScheme: ColorScheme
    
    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill((isDark ? Color.black : Color.white).opacity(opacity)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke((isDark ? Color.white : Color.black).opacity(0.15), lineWidth: 0.5))
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 20, opacity: Double = 0.5, colorScheme: ColorScheme) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, opacity: opacity, colorScheme: colorScheme))
    }
}

class WindowDragTracker {
    var startMouseLocation: NSPoint? = nil
    var startWindowOrigin: NSPoint? = nil
    var isDragging: Bool = false
}
