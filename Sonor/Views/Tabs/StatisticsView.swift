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
        .onChange(of: isIncognitoMode) {
            localIncognitoMode = isIncognitoMode
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UsageStatsUpdated"))) { _ in
            loadStats()
        }
        .onChange(of: isShowingIncognitoExplanation) {
            if !isShowingIncognitoExplanation && pendingIncognitoAnimation {
                pendingIncognitoAnimation = false
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
            milestoneHours = ceil(currentHours)
        } else if currentHours < 20.0 {
            let step = 2.5
            milestoneHours = ceil(currentHours / step) * step
        } else if currentHours < 50.0 {
            let step = 5.0
            milestoneHours = ceil(currentHours / step) * step
        } else if currentHours < 100.0 {
            let step = 10.0
            milestoneHours = ceil(currentHours / step) * step
        } else {
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
            case "zh":
                suffix = "小时"
                label = "目标: \(milestoneHours.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(milestoneHours))" : String(format: "%.1f", milestoneHours)) \(suffix)"
            default: 
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

