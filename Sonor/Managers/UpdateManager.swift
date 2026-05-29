import Foundation
import AppKit
import SwiftUI
import Combine

struct AppConfig: Codable {
    let latest_version: String
    let min_required_version: String
    let update_url: String
}

@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    private var supabaseUrl: String {
        return EnvReader.shared.getValue(for: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        return EnvReader.shared.getValue(for: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private init() {}
    
    func checkForUpdates() {
        Task {
            await fetchConfigAndCheck()
        }
    }
    
    private func fetchConfigAndCheck() async {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else { return }
        
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/app_config?select=*&limit=1") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let configs = try decoder.decode([AppConfig].self, from: data)
                if let config = configs.first {
                    compareVersionsAndAlert(config: config)
                }
            } else {
                print("⚠️ UpdateManager: Non-200 response or invalid response.")
            }
        } catch {
            print("❌ Failed to fetch app_config for update check: \(error)")
        }
    }
    
    private func compareVersionsAndAlert(config: AppConfig) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            print("⚠️ UpdateManager: Could not retrieve current app version.")
            return
        }
        
        print("ℹ️ UpdateManager: Current Version = \(currentVersion), Min Required = \(config.min_required_version), Latest = \(config.latest_version)")
        
        let comparisonToMin = currentVersion.compare(config.min_required_version, options: .numeric)
        let comparisonToLatest = currentVersion.compare(config.latest_version, options: .numeric)
        
        // Jeśli wersja jest równa min_required_version (orderedSame) lub większa (orderedDescending), nie pokazujemy blokującego info o update.
        // Pokazujemy je tylko gdy current < min_required_version (orderedAscending).
        let isLessThanMin = (comparisonToMin == .orderedAscending)
        
        // Jeśli wersja jest równa latest_version (orderedSame) lub większa (orderedDescending), nie pokazujemy info o update.
        // Pokazujemy je tylko gdy current < latest_version (orderedAscending).
        let isLessThanLatest = (comparisonToLatest == .orderedAscending)
        
        if isLessThanMin {
            print("🚨 UpdateManager: Current version is less than minimum required version. Showing blocking alert.")
            showBlockingAlert(url: config.update_url)
        } else if isLessThanLatest {
            print("🔔 UpdateManager: Current version is less than latest version. Showing optional alert.")
            showOptionalAlert(url: config.update_url)
        } else {
            print("✅ UpdateManager: App is up to date (current version >= latest/min required version). No update alert is shown.")
        }
    }
    
    private func showBlockingAlert(url: String) {
        let alert = NSAlert()
        alert.messageText = t("Update Required")
        alert.informativeText = t("You are using an older version of the application that is no longer supported. Please update to continue using Sonor.")
        alert.alertStyle = .critical
        alert.addButton(withTitle: t("Update"))
        alert.addButton(withTitle: t("Quit"))
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let updateURL = URL(string: url) {
                NSWorkspace.shared.open(updateURL)
            }
            NSApplication.shared.terminate(nil)
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func showOptionalAlert(url: String) {
        let alert = NSAlert()
        alert.messageText = t("Update Available")
        alert.informativeText = t("A new version of Sonor is available. Would you like to update now?")
        alert.alertStyle = .informational
        alert.addButton(withTitle: t("Update"))
        alert.addButton(withTitle: t("Later"))
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let updateURL = URL(string: url) {
                NSWorkspace.shared.open(updateURL)
            }
        }
    }
}
