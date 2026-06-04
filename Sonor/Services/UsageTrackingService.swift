import Foundation

class UsageTrackingService {
    static let shared = UsageTrackingService()
    
    private init() {}
    
    func recordUsage(duration: Double, text: String) {
        if UserDefaults.standard.bool(forKey: "isIncognitoMode") {
            return
        }
        let wordCount = text.split(separator: " ").count
        let stat = UsageStat(id: UUID(), date: Date(), duration: duration, wordCount: wordCount)
        var stats = getStats()
        stats.append(stat)
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: "usageStats")
            NotificationCenter.default.post(name: Notification.Name("UsageStatsUpdated"), object: nil)
        }
    }
    
    func getStats() -> [UsageStat] {
        if let data = UserDefaults.standard.data(forKey: "usageStats"),
           let stats = try? JSONDecoder().decode([UsageStat].self, from: data) {
            return stats
        }
        return []
    }
}
