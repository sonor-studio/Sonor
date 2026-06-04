import Foundation

struct LearnedEntry: Equatable {
    let wrong: String
    let correct: String
    let previousValue: String?
}

struct DictionaryNotification: Equatable {
    let wrong: String
    let correct: String
    let learnedEntries: [LearnedEntry]
}
