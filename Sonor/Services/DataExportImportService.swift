import Foundation
import AppKit
import UniformTypeIdentifiers

struct SonorExportData: Codable {
    let settingsData: Data
    let assistants: [VoiceMode]
    let snippets: [String: String]
    let dictionary: [String: String]
    let stats: [UsageStat]
    let history: [MemoryMessage]?
}

@MainActor
class DataExportImportService {
    static let shared = DataExportImportService()
    
    private init() {}
    
    func exportData() {
        // Collect Assistants
        let assistants = VoiceMode.loadAndMigrateModes()
        
        // Collect Dictionary and Snippets
        let dictionary = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
        let snippets = UserDefaults.standard.dictionary(forKey: "snippetsEntries") as? [String: String] ?? [:]
        
        // Collect Stats
        let stats = UsageTrackingService.shared.getStats()
        
        // Collect History (only if File)
        var history: [MemoryMessage]? = nil
        if MessageMemoryManager.shared.historyStorageType == "File" {
            let currentMessages = MessageMemoryManager.shared.messages
            history = currentMessages.map { msg in
                var modMsg = msg
                modMsg.hasAudio = false // Do not export audio links since wav files are not exported
                return modMsg
            }
        }
        
        // Collect Settings
        var settingsToExport: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            // Filter out keys we shouldn't export
            if key.starts(with: "NS") || key.starts(with: "Apple") || key.starts(with: "com.apple") || key.starts(with: "AK") || key.starts(with: "WebKit") { continue }
            if key == "selectedMLXModelId" || key == "selectedWhisperModelId" || key.contains("Bytes") { continue }
            if ["voiceModes", "usageStats", "dictionaryEntries", "snippetsEntries"].contains(key) { continue }
            
            if JSONSerialization.isValidJSONObject([key: value]) {
                settingsToExport[key] = value
            }
        }
        let settingsData = (try? JSONSerialization.data(withJSONObject: settingsToExport)) ?? Data()
        
        let exportData = SonorExportData(
            settingsData: settingsData,
            assistants: assistants,
            snippets: snippets,
            dictionary: dictionary,
            stats: stats,
            history: history
        )
        
        guard let jsonData = try? JSONEncoder().encode(exportData) else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        savePanel.nameFieldStringValue = "SonorBackup_\(formatter.string(from: Date())).json"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? jsonData.write(to: url)
            }
        }
    }
    
    func importData() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    guard let data = try? Data(contentsOf: url),
                          let importedData = try? JSONDecoder().decode(SonorExportData.self, from: data) else {
                        return
                    }
                    
                    // Restore settings
                    if let settingsDict = try? JSONSerialization.jsonObject(with: importedData.settingsData) as? [String: Any] {
                        for (key, value) in settingsDict {
                            UserDefaults.standard.set(value, forKey: key)
                        }
                    }
                    
                    // Restore Assistants
                    if let assistantsData = try? JSONEncoder().encode(importedData.assistants) {
                        UserDefaults.standard.set(assistantsData, forKey: "voiceModes")
                        NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
                    }
                    
                    // Restore Dictionary and Snippets
                    UserDefaults.standard.set(importedData.dictionary, forKey: "dictionaryEntries")
                    UserDefaults.standard.set(importedData.snippets, forKey: "snippetsEntries")
                    
                    // Restore Stats
                    if let statsData = try? JSONEncoder().encode(importedData.stats) {
                        UserDefaults.standard.set(statsData, forKey: "usageStats")
                        NotificationCenter.default.post(name: Notification.Name("UsageStatsUpdated"), object: nil)
                    }
                    
                    // Restore History
                    if let history = importedData.history {
                        // Update MessageMemoryManager if current is File
                        if MessageMemoryManager.shared.historyStorageType == "File" {
                            MessageMemoryManager.shared.messages = history
                            // Trigger save
                            let url = MessageMemoryManager.shared.historyFileURL
                            if let histData = try? JSONEncoder().encode(history) {
                                try? histData.write(to: url, options: [.atomic])
                            }
                        }
                    }
                    
                    // Show success alert
                    let alert = NSAlert()
                    alert.messageText = t("Import Successful")
                    alert.informativeText = t("The data has been imported successfully. Please restart the app manually if some settings did not update.")
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    
                    if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
                        alert.beginSheetModal(for: window, completionHandler: nil)
                    }
                }
            }
        }
    }
}
