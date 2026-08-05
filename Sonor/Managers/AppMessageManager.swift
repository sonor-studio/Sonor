import Foundation
import Combine
import SwiftUI

struct AppMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let header: String
    let description: String
    let content_markdown: String
    let created_at: String?
}

@MainActor
class AppMessageManager: ObservableObject {
    static let shared = AppMessageManager()
    
    @Published var messages: [AppMessage] = []
    @Published var isLoading = false
    @Published var autoShowMessage: AppMessage?
    
    private var supabaseUrl: String {
        return EnvReader.shared.getValue(for: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        return EnvReader.shared.getValue(for: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private init() {
        fetchMessages()
    }
    
    func fetchMessages() {
        Task {
            await fetchMessagesAsync()
        }
    }
    
    private func fetchMessagesAsync() async {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else { return }
        
        self.isLoading = true
        defer { self.isLoading = false }
        
        // Fetch all messages, ordered by created_at descending
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/app_messages?select=*&order=created_at.desc") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    let fetchedMessages = try decoder.decode([AppMessage].self, from: data)
                    self.messages = fetchedMessages
                    
                    if let newest = fetchedMessages.first {
                        let seenMessages = UserDefaults.standard.array(forKey: "seen_app_messages") as? [String] ?? []
                        if !seenMessages.contains(newest.id.uuidString) {
                            self.autoShowMessage = newest
                            self.markAsSeen(newest)
                        }
                    }
                } else {
                    print("AppMessageManager HTTP Error: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("Failed to fetch app messages: \(error)")
        }
    }
    
    func markAsSeen(_ message: AppMessage) {
        var seenMessages = UserDefaults.standard.array(forKey: "seen_app_messages") as? [String] ?? []
        if !seenMessages.contains(message.id.uuidString) {
            seenMessages.append(message.id.uuidString)
            UserDefaults.standard.set(seenMessages, forKey: "seen_app_messages")
        }
    }
}
