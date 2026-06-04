import SwiftUI
import Charts

struct DailyStat: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let wordCount: Int
    let speakingTime: Double 
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
