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
            print("🧠 [MessageMemoryManager] Wczytano \(decoded.count) wiadomości z pliku historii.")
        } catch {
            print("❌ [MessageMemoryManager] Błąd wczytywania historii: \(error)")
            self.messages = []
        }
    }
    
    private func saveToDisk() {
        guard historyStorageType == "File" else { return }
        let url = historyFileURL
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: url, options: [.atomic])
            print("💾 [MessageMemoryManager] Historia zapisana w pliku.")
        } catch {
            print("❌ [MessageMemoryManager] Błąd zapisu historii: \(error)")
        }
    }
    
    private func deleteDiskFile() {
        let url = historyFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
            print("🧹 [MessageMemoryManager] Plik historii został usunięty z dysku.")
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
            print("🧠 [MessageMemoryManager] Pomijam zapisywanie pustej wiadomości.")
            return
        }
        
        if UserDefaults.standard.bool(forKey: "isIncognitoMode") {
            print("🕵️‍♂️ [MessageMemoryManager] Tryb Incognito: Wiadomość NIE została zapisana.")
            return
        }
        
        let msg = MemoryMessage(id: UUID(), text: trimmed, date: Date())
        messages.append(msg)
        
        if historyStorageType == "File" {
            saveToDisk()
        }
        
        // Obliczamy przybliżony rozmiar w pamięci (w bajtach)
        var totalBytes = 0
        for m in messages {
            totalBytes += m.text.utf8.count
        }
        
        let kb = Double(totalBytes) / 1024.0
        let mb = kb / 1024.0
        
        print("🧠 [MessageMemoryManager] Zapisano wiadomość w pamięci.")
        print("🧠 [MessageMemoryManager] Liczba wiadomości: \(messages.count)")
        if mb > 1.0 {
            print(String(format: "🧠 [MessageMemoryManager] Szacowany rozmiar: %.2f MB", mb))
        } else if kb > 1.0 {
            print(String(format: "🧠 [MessageMemoryManager] Szacowany rozmiar: %.2f KB", kb))
        } else {
            print("🧠 [MessageMemoryManager] Szacowany rozmiar: \(totalBytes) bajtów")
        }
    }
    
    func clearHistory() {
        messages.removeAll()
        if historyStorageType == "File" {
            deleteDiskFile()
        }
        print("🧹 [MessageMemoryManager] Historia wyczyszczona.")
    }
    
    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        if historyStorageType == "File" {
            saveToDisk()
        }
    }
}

