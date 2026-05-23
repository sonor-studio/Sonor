import Foundation
import Security
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isLoggedIn: Bool = false
    @Published var currentUserEmail: String? = nil
    
    private let tokenKey = "sonor.supabase.access_token"
    private let emailKey = "sonor.supabase.user_email"
    
    private var supabaseUrl: String {
        return EnvReader.shared.getValue(for: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        return EnvReader.shared.getValue(for: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private init() {
        checkLocalSession()
    }
    
    private func checkLocalSession() {
        if let token = getFromKeychain(key: tokenKey), !token.isEmpty {
            isLoggedIn = true
            currentUserEmail = getFromKeychain(key: emailKey)
            print("✅ Wykryto sesję lokalną dla użytkownika: \(currentUserEmail ?? "Nieznany")")
        } else {
            isLoggedIn = false
            currentUserEmail = nil
            print("ℹ️ Brak aktywnej sesji lokalnej (Darmowy użytkownik)")
        }
    }
    
    func login(email: String, password: String) async throws {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase keys in .env file"])
        }
        
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/token?grant_type=password") else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                
                // Zapisz do Keychain
                saveToKeychain(key: tokenKey, value: accessToken)
                saveToKeychain(key: emailKey, value: email)
                
                self.isLoggedIn = true
                self.currentUserEmail = email
            } else {
                throw NSError(domain: "AuthError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Error parsing token response"])
            }
        } else {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func register(email: String, password: String) async throws {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase keys in .env file"])
        }
        
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/signup") else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        
        if httpResponse.statusCode == 200 {
            // Czasem signup zwraca sesję, czasem nie. Możemy wymagać potwierdzenia email,
            // ale założymy że logujemy automatycznie lub pytamy usera o logowanie.
            // Dla prostoty spróbujmy zalogować od razu.
            try await login(email: email, password: password)
        } else {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func logout() {
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: emailKey)
        self.isLoggedIn = false
        self.currentUserEmail = nil
    }
    
    private func extractErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["error_description"] as? String ?? json["msg"] as? String {
            return msg
        }
        return "An unexpected server error occurred."
    }
    
    // MARK: - Keychain Helpers
    
    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
