import Foundation

class EnvReader {
    static let shared = EnvReader()
    
    private var envVars: [String: String] = [:]
    
    private init() {
        loadEnv()
    }
    
    private func loadEnv() {
        guard let envPath = Bundle.main.path(forResource: ".env", ofType: nil) else {
            print("⚠️ Nie znaleziono pliku .env w Bundle.main")
            return
        }
        
        do {
            let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
            let lines = envContent.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }
                
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"\'"))
                    envVars[key] = value
                }
            }
        } catch {
            print("❌ Błąd odczytu pliku .env: \(error.localizedDescription)")
        }
    }
    
    func getValue(for key: String) -> String? {
        return envVars[key]
    }
}
