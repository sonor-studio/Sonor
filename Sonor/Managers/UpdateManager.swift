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
            }
        } catch {
        }
    }
    private func compareVersionsAndAlert(config: AppConfig) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }
        let comparisonToMin = currentVersion.compare(config.min_required_version, options: .numeric)
        let comparisonToLatest = currentVersion.compare(config.latest_version, options: .numeric)
        let isLessThanMin = (comparisonToMin == .orderedAscending)
        let isLessThanLatest = (comparisonToLatest == .orderedAscending)
        if isLessThanMin {
            showBlockingAlert(url: config.update_url, currentVersion: currentVersion, latestVersion: config.latest_version)
        } else if isLessThanLatest {
            showOptionalAlert(url: config.update_url, currentVersion: currentVersion, latestVersion: config.latest_version)
        } else {
        }
    }
    private func showBlockingAlert(url: String, currentVersion: String, latestVersion: String) {
        let alert = NSAlert()
        alert.messageText = t("Update Required")
        alert.informativeText = String(format: t("You are using an older version of the application that is no longer supported.\n\nCurrent version: %@\nLatest version: %@\n\nPlease update to continue using Sonor."), currentVersion, latestVersion)
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
    private func showOptionalAlert(url: String, currentVersion: String, latestVersion: String) {
        let alert = NSAlert()
        alert.messageText = t("Update Available")
        alert.informativeText = String(format: t("A new version of Sonor is available.\n\nCurrent version: %@\nLatest version: %@\n\nWould you like to update now?"), currentVersion, latestVersion)
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
