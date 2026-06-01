import SwiftUI
import Charts
struct StatisticsView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var localizer = LocalizationManager.shared
    @State private var stats: [UsageStat] = []
    @AppStorage("isIncognitoMode") private var isIncognitoMode = false
    @ObservedObject private var memoryManager = MessageMemoryManager.shared
    @State private var isShowingBenchmarkSheet = false
    @State private var isShowingIncognitoExplanation = false
    @State private var isShowingExplanationFromInfoButton = false
    @State private var pendingIncognitoAnimation = false
    @State private var localIncognitoMode = false
    
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
                .preferredColorScheme(colorScheme)
        }
        .sheet(isPresented: $isShowingIncognitoExplanation) {
            IncognitoExplanationView(isFromInfo: isShowingExplanationFromInfoButton)
                .preferredColorScheme(colorScheme)
        }
        .onAppear {
            localIncognitoMode = isIncognitoMode
            loadStats()
        }
        .onChange(of: isIncognitoMode) { newValue in
            localIncognitoMode = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UsageStatsUpdated"))) { _ in
            loadStats()
        }
        .onChange(of: isShowingIncognitoExplanation) { newValue in
            if !newValue && pendingIncognitoAnimation {
                pendingIncognitoAnimation = false
                // Small delay to ensure sheet is fully dismissed before animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: NSNotification.Name("PlayIncognitoAnimation"), object: NSNumber(value: true))
                }
            }
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
                    get: { localIncognitoMode },
                    set: { newValue in
                        localIncognitoMode = newValue
                        
                        // Defer heavy AppStorage write and sheet presentation to allow smooth animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isIncognitoMode = newValue
                            
                            if newValue {
                                if !UserDefaults.standard.bool(forKey: "skipIncognitoExplanation") {
                                    pendingIncognitoAnimation = true
                                    isShowingExplanationFromInfoButton = false
                                    isShowingIncognitoExplanation = true
                                } else {
                                    NotificationCenter.default.post(name: NSNotification.Name("PlayIncognitoAnimation"), object: NSNumber(value: true))
                                }
                            } else {
                                pendingIncognitoAnimation = false
                                NotificationCenter.default.post(name: NSNotification.Name("PlayIncognitoAnimation"), object: NSNumber(value: false))
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
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
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

struct RamHistoryView: View {
    @ObservedObject var memoryManager: MessageMemoryManager
    let colorScheme: ColorScheme
    
    // Hover state trackers for RAM History
    @State private var hoveredCardId: UUID? = nil
    @State private var hoveredCopyId: UUID? = nil
    @State private var hoveredTrashId: UUID? = nil
    @State private var isHoveringClearHistory = false
    @State private var isShowingRamExplanation = false
    
    // Pagination state
    @State private var currentPage = 0
    let itemsPerPage = 5
    
    var reversedMessages: [MemoryMessage] {
        memoryManager.messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.reversed()
    }
    
    var totalPages: Int {
        let count = reversedMessages.count
        guard count > 0 else { return 1 }
        return Int(ceil(Double(count) / Double(itemsPerPage)))
    }
    
    var paginatedMessages: [MemoryMessage] {
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, reversedMessages.count)
        guard startIndex < reversedMessages.count else { return [] }
        return Array(reversedMessages[startIndex..<endIndex])
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(t("Text History"))
                        .font(.system(size: 20, weight: .bold))
                    
                    // Premium monochrome storage indicator badge
                    let isRAM = memoryManager.historyStorageType == "RAM"
                    HStack(spacing: 5) {
                        Image(systemName: isRAM ? "memorychip" : "doc.text.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(t(isRAM ? "Temporary RAM" : "Local File"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundColor(.primary)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.leading, 4)
                    
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
                if !reversedMessages.isEmpty {
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
            
            if reversedMessages.isEmpty {
                // Modern empty state with dashed borders and clock/file icon
                VStack(spacing: 16) {
                    Image(systemName: memoryManager.historyStorageType == "File" ? "doc.text.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(t(memoryManager.historyStorageType == "File" ? "No saved texts" : "No saved texts in RAM"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(t(memoryManager.historyStorageType == "File" ? "Every processed text will appear here and be stored securely in your persistent local history file." : "Every processed text will appear here temporarily. Closing Sonor or clearing the history will permanently delete this data."))
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
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(paginatedMessages) { msg in
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
                    
                    // Premium Pagination Controls
                    if totalPages > 1 {
                        HStack(spacing: 20) {
                            Spacer()
                            
                            Button(action: {
                                if currentPage > 0 {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPage -= 1
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(currentPage > 0 ? Color.primary.opacity(0.08) : Color.clear)
                                .foregroundColor(currentPage > 0 ? .primary : .secondary.opacity(0.3))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentPage == 0)
                            
                            Text(String(format: t("Page %d of %d"), currentPage + 1, totalPages))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 80)
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                if currentPage < totalPages - 1 {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPage += 1
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(currentPage < totalPages - 1 ? Color.primary.opacity(0.08) : Color.clear)
                                .foregroundColor(currentPage < totalPages - 1 ? .primary : .secondary.opacity(0.3))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentPage == totalPages - 1)
                            
                            Spacer()
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
        .onChange(of: reversedMessages.count) { newCount in
            let maxPage = max(0, Int(ceil(Double(newCount) / Double(itemsPerPage))) - 1)
            if currentPage > maxPage {
                currentPage = maxPage
            }
        }
        .sheet(isPresented: $isShowingRamExplanation) {
            RamHistoryExplanationView()
                .preferredColorScheme(colorScheme)
        }
    }
}


struct MessageCardView: View {
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

struct DailyStat: Identifiable, Equatable {
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

struct ActivityChartView: View {
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
            .animation(nil, value: dailyStats)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
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

struct PaceChartView: View {
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
            .animation(nil, value: dailyStats)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
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
