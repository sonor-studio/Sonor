import Foundation
import SwiftUI
import Combine

struct MemoryMessage: Identifiable {
    let id: UUID
    let text: String
    let date: Date
}

@MainActor
class MessageMemoryManager: ObservableObject {
    static let shared = MessageMemoryManager()
    
    @Published var messages: [MemoryMessage] = []
    
    private init() {}
    
    func saveMessage(_ text: String) {
        if UserDefaults.standard.bool(forKey: "isIncognitoMode") {
            print("🕵️‍♂️ [MessageMemoryManager] Tryb Incognito: Wiadomość NIE została zapisana w RAM.")
            return
        }
        
        let msg = MemoryMessage(id: UUID(), text: text, date: Date())
        messages.append(msg)
        
        // Obliczamy przybliżony rozmiar w pamięci (w bajtach)
        var totalBytes = 0
        for m in messages {
            totalBytes += m.text.utf8.count
        }
        
        let kb = Double(totalBytes) / 1024.0
        let mb = kb / 1024.0
        
        print("🧠 [MessageMemoryManager] Zapisano wiadomość w RAM.")
        print("🧠 [MessageMemoryManager] Liczba zapisanych wiadomości: \(messages.count)")
        if mb > 1.0 {
            print(String(format: "🧠 [MessageMemoryManager] Szacowany rozmiar w pamięci: %.2f MB", mb))
        } else if kb > 1.0 {
            print(String(format: "🧠 [MessageMemoryManager] Szacowany rozmiar w pamięci: %.2f KB", kb))
        } else {
            print("🧠 [MessageMemoryManager] Szacowany rozmiar w pamięci: \(totalBytes) bajtów")
        }
    }
    
    func clearHistory() {
        messages.removeAll()
        print("🧹 [MessageMemoryManager] Historia wyczyszczona.")
    }
    
    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }
}
