import SwiftUI

struct CapsuleHUDView: View {
    @ObservedObject var controller: AppController
    
    @AppStorage("hotkeyMode") private var hotkeyMode: HotkeyMode = .click
    
    private var targetWidth: CGFloat {
        if !controller.isRecording {
            return 232.0
        } else {
            return hotkeyMode == .hold ? 232.0 : 180.0
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
    @State private var dragStartMouseLocation: NSPoint? = nil
    @State private var dragStartWindowOrigin: NSPoint? = nil
    
    // Podwidoki do odciążenia kompilatora i zapobieżenia timeoutom type-checkingu
    private var assistantSelector: some View {
        Button(action: { withAnimation { showList.toggle() } }) {
            HStack {
                Text(t(controller.currentMode?.name ?? "Wybierz tryb"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: showList ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .frame(width: 284, height: 40)
            .contentShape(Rectangle())
            .darkGlass(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    
    private var audioWavesView: some View {
        let levels = Array(controller.audioLevels.suffix(36))
        return HStack(spacing: 2) {
            ForEach(0..<levels.count, id: \.self) { index in
                let level = levels[index]
                let barHeight = CGFloat(2 + (level * 350))
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(controller.isPaused ? Color.white.opacity(0.4) : Color.white)
                    .frame(width: 3, height: min(barHeight, 40))
                    .animation(.spring(response: 0.1, dampingFraction: 0.5), value: level)
            }
        }
        .frame(width: width, height: 40)
        .clipShape(Capsule())
    }
    
    private var loaderView: some View {
        HStack(spacing: 8) {
            Text(t(controller.statusText))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
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
                        Color.white,
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
                                .foregroundColor(.white)
                            Spacer()
                            if controller.currentMode?.id == mode.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            controller.currentMode?.id == mode.id ? Color.white.opacity(0.2) :
                            (hoveredModeID == mode.id ? Color.white.opacity(0.1) : Color.clear)
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
        .darkGlass(cornerRadius: 12, opacity: 0.7)
        .padding(.bottom, 96)
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
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.leading, 12)
                
                Text("\"\(notification.wrong)\" ➔ \"\(notification.correct)\"")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        controller.undoDictionaryEntry()
                    }
                }) {
                    Text("Undo")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.trailing, 8)
            }
            .frame(width: 284, height: 40)
            .darkGlass(cornerRadius: 20)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        )
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Główna zawartość (Dół)
            VStack(spacing: 8) {
                if let _ = controller.activeDictionaryNotification {
                    dictionaryNotificationView
                } else {
                    // Pole wyboru asystenta
                    if AuthManager.shared.isLoggedIn {
                        assistantSelector
                    }
                    
                    // Dolny pasek: Fale/Loader + Przycisk Pauza + Przycisk X
                    HStack(spacing: 12) {
                        ZStack {
                            if !isProcessing {
                                audioWavesView
                                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.5).combined(with: .opacity)))
                            } else {
                                loaderView
                                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.5).combined(with: .opacity)))
                            }
                        }
                        .frame(width: width, height: height)
                        .darkGlass(cornerRadius: 20)
                        
                        // Przycisk Pauza / Wznów
                        if showPauseButton {
                            Button(action: { controller.togglePause() }) {
                                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                                    .darkGlass(cornerRadius: 20)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                        
                        // Przycisk X (Anuluj)
                        Button(action: { controller.cancelRecording() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                                .darkGlass(cornerRadius: 20)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }
            
            // Lista asystentów
            if showList {
                dropdownListView
            }
        }
        .frame(width: 350, height: 600, alignment: .bottom)
        .opacity(opacity)
        .colorScheme(.dark)
        .onAppear {
            controller.reloadModes()
            showPauseButton = hotkeyMode == .click && controller.isRecording
            width = targetWidth
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1.0
            }
        }
        .onChange(of: hotkeyMode) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPauseButton = hotkeyMode == .click && controller.isRecording
                width = targetWidth
            }
        }
        .onChange(of: controller.isRecording) { isRecording in
            if !isRecording {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showPauseButton = false
                    width = 232.0
                    height = 40
                    isProcessing = true
                }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showPauseButton = hotkeyMode == .click
                    width = hotkeyMode == .hold ? 232.0 : 180.0
                    height = 40
                    isProcessing = false
                }
            }
        }
        .onChange(of: controller.statusText) { status in
            if status == "Done!" {
                withAnimation(.easeOut(duration: 0.5)) {
                    opacity = 0.0
                }
            } else if status == "Listening..." {
                withAnimation(.easeIn(duration: 0.2)) {
                    opacity = 1.0
                }
            }
        }
        .onChange(of: controller.activeDictionaryNotification) { notification in
            if notification == nil && !controller.isRecording {
                withAnimation(.easeOut(duration: 0.5)) {
                    opacity = 0.0
                }
            } else {
                withAnimation(.easeIn(duration: 0.2)) {
                    opacity = 1.0
                }
            }
        }
        .highPriorityGesture(dragGesture)
    }
    
    // Gest przeciągania
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let currentMouse = NSEvent.mouseLocation
                guard let window = controller.hudWindow else { return }
                
                if dragStartMouseLocation == nil {
                    dragStartMouseLocation = currentMouse
                    dragStartWindowOrigin = window.frame.origin
                }
                
                guard let startMouse = dragStartMouseLocation,
                      let startOrigin = dragStartWindowOrigin else { return }
                
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
                dragStartMouseLocation = nil
                dragStartWindowOrigin = nil
            }
    }
}

struct DarkGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double = 0.5
    
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(opacity)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }
}

extension View {
    func darkGlass(cornerRadius: CGFloat = 20, opacity: Double = 0.5) -> some View {
        self.modifier(DarkGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}
