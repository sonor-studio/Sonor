import Foundation
import SwiftUI
import Combine

struct MemoryMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
}

@MainActor
class MessageMemoryManager: ObservableObject {
    static let shared = MessageMemoryManager()
    @Published var messages: [MemoryMessage] = []
    @Published var historyStorageType: String = UserDefaults.standard.string(forKey: "historyStorageType") ?? "RAM" {
        didSet {
            UserDefaults.standard.set(historyStorageType, forKey: "historyStorageType")
        }
    }
    var historyFileURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sonorURL = appSupportURL.appendingPathComponent("Sonor", isDirectory: true)
        if !fileManager.fileExists(atPath: sonorURL.path) {
            try? fileManager.createDirectory(at: sonorURL, withIntermediateDirectories: true, attributes: nil)
        }
        return sonorURL.appendingPathComponent("history.json")
    }
    private init() {
        loadHistory()
    }
    func loadHistory() {
        guard historyStorageType == "File" else {
            self.messages = []
            return
        }
        let url = historyFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.messages = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([MemoryMessage].self, from: data)
            self.messages = decoded
        } catch {
            self.messages = []
        }
    }
    private func saveToDisk() {
        guard historyStorageType == "File" else { return }
        let url = historyFileURL
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: url, options: [.atomic])
        } catch {
        }
    }
    private func deleteDiskFile() {
        let url = historyFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    func switchToFileMode() {
        historyStorageType = "File"
        saveToDisk()
    }
    func switchToRAMMode() {
        historyStorageType = "RAM"
        deleteDiskFile()
    }
    func saveMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        if UserDefaults.standard.bool(forKey: "isIncognitoMode") {
            return
        }
        let msg = MemoryMessage(id: UUID(), text: trimmed, date: Date())
        messages.append(msg)
        if historyStorageType == "File" {
            saveToDisk()
        }
        var totalBytes = 0
        for m in messages {
            totalBytes += m.text.utf8.count
        }
        let kb = Double(totalBytes) / 1024.0
        let mb = kb / 1024.0
        if mb > 1.0 {
        } else if kb > 1.0 {
        } else {
        }
    }
    func clearHistory() {
        messages.removeAll()
        if historyStorageType == "File" {
            deleteDiskFile()
        }
    }
    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        if historyStorageType == "File" {
            saveToDisk()
        }
    }
}

