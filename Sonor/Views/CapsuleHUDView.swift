import SwiftUI
import Combine
import AppKit

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
    @State private var showPauseButton = false
    @State private var width: CGFloat = 180
    @State private var height: CGFloat = 40
    @State private var isProcessing = false
    @State private var opacity: Double = 0
    @State private var showList = false
    @State private var hoveredModeID: UUID? = nil
    @State private var dragTracker = WindowDragTracker()
    @State private var recordingDuration: TimeInterval = 0
    @State private var dictProgress: CGFloat = 1.0
    @State private var copyProgress: CGFloat = 1.0
    @State private var isCopied: Bool = false
    @State private var isUndone: Bool = false
    private let recordingTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private var assistantSelector: some View {
        Button(action: {
            if !dragTracker.isDragging { withAnimation { showList.toggle() } }
        }) {
            HStack {
                ZStack(alignment: .leading) {
                    Text(t(controller.currentMode?.name ?? "Wybierz tryb"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .id(controller.currentMode?.id ?? UUID())
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
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
                        .buttonStyle(NoAnimButtonStyle())
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
                        .fill(controller.isPaused ? textColor.opacity(0.4) : textColor)
                        .frame(width: 3, height: min(barHeight, 40))
                        .animation(.spring(response: 0.1, dampingFraction: 0.5), value: level)
                }
            }
            Spacer()
                .frame(width: 14)
            if controller.isRecording {
                Text(formatDuration(recordingDuration))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(controller.isPaused ? textColor.opacity(0.4) : textColor.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer()
                .frame(width: 12)
        }
        .frame(width: width, height: 40)
        .clipShape(Capsule())
    }
    private var textColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }
    
    private var loaderView: some View {
        HStack(spacing: 8) {
            Text(t(controller.statusText))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textColor)
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
                        textColor,
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
                                .foregroundColor(textColor)
                            Spacer()
                            if controller.currentMode?.id == mode.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(textColor)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            controller.currentMode?.id == mode.id ? Color.primary.opacity(0.2) :
                            (hoveredModeID == mode.id ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .cornerRadius(8)
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
            ZStack(alignment: .bottomLeading) {
                Button(action: {}) { Color.white.opacity(0.001) }
                    .buttonStyle(NoAnimButtonStyle())
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
                        if !dragTracker.isDragging {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isUndone = true
                            }
                            controller.undoDictionaryEntry(delayHide: true)
                        }
                    }) {
                        ZStack {
                            if isUndone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text(t("Undo"))
                                    .font(.system(size: 11, weight: .bold))
                                    .fixedSize()
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .foregroundColor(effectiveColorScheme == .dark ? .black : .white)
                        .padding(.horizontal, isUndone ? 0 : 10)
                        .frame(width: isUndone ? 24 : nil, height: 24)
                        .background(effectiveColorScheme == .dark ? Color.white : Color.black)
                        .clipShape(Capsule())
                    }
                                    .buttonStyle(NoAnimButtonStyle())
                    .focusable(false)
                    .padding(.trailing, 8)
                }
                .frame(width: 284, height: 40)
                
                Capsule()
                    .fill(effectiveColorScheme == .dark ? Color.white : Color.black)
                    .frame(width: 284 * dictProgress, height: 4)
                    .opacity(isUndone ? 0 : 1)
            }
            .frame(width: 284, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
            .onAppear {
                isUndone = false
                dictProgress = 1.0
                withAnimation(.linear(duration: 5.0)) {
                    dictProgress = 0.0
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .simultaneousGesture(dragGesture)
        )
    }
    private var copyNotificationView: some View {
        guard let _ = controller.activeCopyNotification else { return AnyView(EmptyView()) }
        return AnyView(
            ZStack(alignment: .bottomLeading) {
                Button(action: {}) { Color.white.opacity(0.001) }
                    .buttonStyle(NoAnimButtonStyle())
                HStack(spacing: 8) {
                    Text(t("Nie wykryto pola"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.leading, 14)
                    Spacer()
                    Button(action: {
                        if !dragTracker.isDragging {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isCopied = true
                            }
                            controller.copyNotificationTextToClipboard(delayHide: true)
                        }
                    }) {
                        ZStack {
                            if isCopied {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text(t("Skopiuj"))
                                    .font(.system(size: 11, weight: .bold))
                                    .fixedSize()
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .foregroundColor(effectiveColorScheme == .dark ? .black : .white)
                        .padding(.horizontal, isCopied ? 0 : 10)
                        .frame(width: isCopied ? 24 : nil, height: 24)
                        .background(effectiveColorScheme == .dark ? Color.white : Color.black)
                        .clipShape(Capsule())
                    }
                                    .buttonStyle(NoAnimButtonStyle())
                    .focusable(false)
                    .padding(.trailing, 8)
                }
                .frame(width: 284, height: 40)
                
                Capsule()
                    .fill(effectiveColorScheme == .dark ? Color.white : Color.black)
                    .frame(width: 284 * copyProgress, height: 4)
                    .opacity(isCopied ? 0 : 1)
            }
            .frame(width: 284, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .safeGlassEffect(cornerRadius: 20)
            .onAppear {
                isCopied = false
                copyProgress = 1.0
                withAnimation(.linear(duration: 5.0)) {
                    copyProgress = 0.0
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .simultaneousGesture(dragGesture)
        )
    }
    var body: some View {
        VStack(spacing: 8) {
            if showList {
                dropdownListView
            }
            ZStack(alignment: .bottom) {
                if let _ = controller.activeDictionaryNotification {
                    dictionaryNotificationView
                        .zIndex(2)
                } else if let _ = controller.activeCopyNotification {
                    copyNotificationView
                        .zIndex(2)
                } else {
                    VStack(spacing: 8) {
                        if AuthManager.shared.isLoggedIn && modelManager.gemmaState == .downloaded {
                            if !isInitializing && !isFinalState && controller.isRecording {
                                assistantSelector
                                    .transition(.asymmetric(insertion: .offset(y: 40).combined(with: .scale(scale: 0.1)).combined(with: .opacity), removal: .offset(y: 40).combined(with: .scale(scale: 0.1)).combined(with: .opacity)))
                                    .zIndex(0)
                            }
                        }
                        HStack(spacing: (isInitializing || isFinalState) ? -40 : 12) {
                            Button(action: {
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
                            .buttonStyle(NoAnimButtonStyle())
                            .focusable(false)
                            .simultaneousGesture(dragGesture)
                            .zIndex(1)
                            if showPauseButton && !isInitializing && !isFinalState {
                                Button(action: {
                                    if !dragTracker.isDragging { controller.togglePause() }
                                }) {
                                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(textColor)
                                        .frame(width: 40, height: 40)
                                        .contentShape(Rectangle())
                                        .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
                                }
                                .buttonStyle(NoAnimButtonStyle())
                                .focusable(false)
                                .simultaneousGesture(dragGesture)
                                .transition(.asymmetric(insertion: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity), removal: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity)))
                                .zIndex(0)
                            }
                            if !isInitializing && !isFinalState {
                                Button(action: {
                                    if !dragTracker.isDragging { controller.cancelRecording() }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(textColor)
                                        .frame(width: 40, height: 40)
                                        .contentShape(Rectangle())
                                        .glass(cornerRadius: 20, colorScheme: effectiveColorScheme)
                                }
                                .buttonStyle(NoAnimButtonStyle())
                                .focusable(false)
                                .simultaneousGesture(dragGesture)
                                .transition(.asymmetric(insertion: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity), removal: .offset(x: -30).combined(with: .scale(scale: 0.1)).combined(with: .opacity)))
                                .zIndex(0)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(1)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.activeDictionaryNotification != nil)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.activeCopyNotification != nil)
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
        .onChange(of: controller.isRecording) {
            if !controller.isRecording {
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
                    isProcessing = controller.statusText != "Listening..." && controller.statusText != "Paused"
                }
            }
        }
        .onChange(of: controller.statusText) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3)) {
                width = targetWidth
                isProcessing = controller.statusText != "Listening..." && controller.statusText != "Paused"
            }
            if isFinalState {
                if controller.activeDictionaryNotification == nil && controller.activeCopyNotification == nil {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        opacity = 0.0
                    }
                }
                showList = false
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    opacity = 1.0
                }
                showList = false
            }
        }
        .onChange(of: controller.activeDictionaryNotification) {
            if controller.activeDictionaryNotification == nil && controller.activeCopyNotification == nil && !controller.isRecording {
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
        .onChange(of: controller.activeCopyNotification) {
            if controller.activeCopyNotification == nil {
                isCopied = false
            }
            if controller.activeDictionaryNotification == nil && controller.activeCopyNotification == nil && !controller.isRecording {
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
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let currentMouse = NSEvent.mouseLocation
                guard let window = WindowManager.shared.hudWindow else { return }
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
                    let screenFrame = screen.visibleFrame
                    let leftMargin: CGFloat = 33
                    let rightMargin: CGFloat = 350 - leftMargin 
                    let minXBound = screenFrame.minX - leftMargin
                    let maxXBound = screenFrame.maxX - rightMargin
                    let visibleHeight = showList ? CGFloat(296) : CGFloat(88)
                    let minYBound = screenFrame.minY
                    let maxYBound = screenFrame.maxY - visibleHeight
                    newX = max(minXBound, min(newX, maxXBound))
                    newY = max(minYBound, min(newY, maxYBound))
                }
                window.setFrameOrigin(NSPoint(x: newX, y: newY))
            }
            .onEnded { _ in
                if let window = WindowManager.shared.hudWindow {
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
    var opacity: Double = 1.0
    var colorScheme: ColorScheme
    
    func body(content: Content) -> some View {
        content
            .safeGlassEffect(cornerRadius: cornerRadius)
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 20, opacity: Double = 1.0, colorScheme: ColorScheme) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, opacity: opacity, colorScheme: colorScheme))
    }
}

struct NoAnimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

class WindowDragTracker {
    var startMouseLocation: NSPoint? = nil
    var startWindowOrigin: NSPoint? = nil
    var isDragging: Bool = false
}
