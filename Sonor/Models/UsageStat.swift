import Foundation

struct UsageStat: Codable, Identifiable {
    let id: UUID
    let date: Date
    let duration: Double 
    let wordCount: Int
}
