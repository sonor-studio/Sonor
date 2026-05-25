import Foundation
import Security
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isLoggedIn: Bool = false
    @Published var currentUserEmail: String? = nil
    @Published var currentUserCreatedAt: Date? = nil
    
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
            Task {
                await fetchUserDetails()
            }
        } else {
            isLoggedIn = false
            currentUserEmail = nil
            currentUserCreatedAt = nil
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
                Task {
                    await fetchUserDetails()
                }
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
        self.currentUserCreatedAt = nil
    }
    
    func deleteAccount() async throws {
        print("[AuthManager] Rozpoczęcie procesu usuwania konta...")
        
        let token = getFromKeychain(key: tokenKey)
        guard let token = token, !token.isEmpty else {
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Brak tokenu."])
        }
        
        // 1. Pobierz ID uzytkownika zeby usunac profil
        guard let userUrl = URL(string: "\(supabaseUrl)/auth/v1/user") else { throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Błąd URL."]) }
        var userReq = URLRequest(url: userUrl)
        userReq.httpMethod = "GET"
        userReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        userReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (uData, uResp) = try await URLSession.shared.data(for: userReq)
        if let uHttp = uResp as? HTTPURLResponse, uHttp.statusCode == 200,
           let uJson = try? JSONSerialization.jsonObject(with: uData) as? [String: Any],
           let userId = uJson["id"] as? String {
            
            print("[AuthManager] Krok 1: Usuwanie z public.profiles dla ID: \(userId)")
            if let profUrl = URL(string: "\(supabaseUrl)/rest/v1/profiles?id=eq.\(userId)") {
                var pReq = URLRequest(url: profUrl)
                pReq.httpMethod = "DELETE"
                pReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                pReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (_, pResp) = try await URLSession.shared.data(for: pReq)
                if let pHttp = pResp as? HTTPURLResponse {
                    print("[AuthManager] Status usunięcia z profiles: \(pHttp.statusCode)")
                }
            }
        }
        
        print("[AuthManager] Krok 2: Usuwanie z auth.users przez RPC delete_own_user")
        guard let rpcUrl = URL(string: "\(supabaseUrl)/rest/v1/rpc/delete_own_user") else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Błąd URL dla RPC."])
        }
        
        var rpcReq = URLRequest(url: rpcUrl)
        rpcReq.httpMethod = "POST"
        rpcReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        rpcReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (rData, rResp) = try await URLSession.shared.data(for: rpcReq)
        guard let rHttp = rResp as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Brak odpowiedzi od serwera."])
        }
        
        print("[AuthManager] Status odpowiedzi RPC delete_own_user: \(rHttp.statusCode)")
        
        if (200...299).contains(rHttp.statusCode) {
            print("[AuthManager] Sukces: Konto zostało całkowicie usunięte.")
            await MainActor.run {
                self.logout()
            }
        } else if rHttp.statusCode == 404 {
            throw NSError(domain: "AuthError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Brak funkcji 'delete_own_user' w bazie. Stwórz ją w SQL Editorze w Supabase."])
        } else {
            let errorMsg = extractErrorMessage(from: rData)
            throw NSError(domain: "AuthError", code: rHttp.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func updatePassword(newPassword: String) async throws {
        print("[AuthManager] Rozpoczęcie zmiany hasła...")
        
        let token = getFromKeychain(key: tokenKey)
        guard let token = token, !token.isEmpty else {
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Brak tokenu. Zaloguj się ponownie."])
        }
        
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/user") else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Błąd URL."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["password": newPassword]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Brak odpowiedzi od serwera."])
        }
        
        if httpResponse.statusCode == 200 {
            print("[AuthManager] Hasło zostało pomyślnie zmienione.")
        } else {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func fetchUserDetails() async {
        print("[AuthManager] fetchUserDetails() rozpoczęte...")
        
        let token = getFromKeychain(key: tokenKey)
        print("[AuthManager] Status tokenu: \(token != nil ? "obecny (długość: \(token!.count))" : "BRAK")")
        
        guard let token = token, !token.isEmpty else {
            print("[AuthManager] Przerwano: Brak tokenu w Keychain.")
            return 
        }
        
        print("[AuthManager] supabaseUrl: '\(supabaseUrl)', anonKey pusta: \(supabaseAnonKey.isEmpty)")
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            print("[AuthManager] Przerwano: Brak kluczy Supabase.")
            return 
        }
        
        // 1. Pobierz ID użytkownika z auth/v1/user
        guard let userUrl = URL(string: "\(supabaseUrl)/auth/v1/user") else { 
            print("[AuthManager] Przerwano: Niepoprawny URL auth/v1/user")
            return 
        }
        var userRequest = URLRequest(url: userUrl)
        userRequest.httpMethod = "GET"
        userRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        userRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            print("[AuthManager] Pobieranie danych użytkownika z \(userUrl)...")
            let (userData, userResponse) = try await URLSession.shared.data(for: userRequest)
            guard let userHttpResponse = userResponse as? HTTPURLResponse else {
                print("[AuthManager] Przerwano: Brak odpowiedzi HTTP dla auth/v1/user")
                return
            }
            
            print("[AuthManager] Status odpowiedzi auth/v1/user: \(userHttpResponse.statusCode)")
            guard (200...299).contains(userHttpResponse.statusCode) else {
                let rawBody = String(data: userData, encoding: .utf8) ?? ""
                print("[AuthManager] Przerwano: Błąd HTTP dla auth/v1/user: \(userHttpResponse.statusCode), odpowiedź: \(rawBody)")
                
                // Jeśli sesja wygasła (401 / 403), wyloguj użytkownika, aby nie wisiał w martwym stanie
                if userHttpResponse.statusCode == 401 || userHttpResponse.statusCode == 403 {
                    print("[AuthManager] Sesja wygasła! Wykonuję automatyczne wylogowanie...")
                    await MainActor.run {
                        self.logout()
                    }
                }
                return 
            }
            
            guard let userJson = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
                  let userId = userJson["id"] as? String else {
                print("[AuthManager] Przerwano: Nie udało się sparsować ID użytkownika z JSON.")
                return 
            }
            
            print("[AuthManager] Pobrano ID użytkownika: \(userId)")
            
            // 2. Pobierz profil z tabeli profiles
            guard let profileUrl = URL(string: "\(supabaseUrl)/rest/v1/profiles?id=eq.\(userId)&select=*") else { 
                print("[AuthManager] Przerwano: Niepoprawny URL profiles")
                return 
            }
            print("[AuthManager] Pobieranie profilu z \(profileUrl)...")
            var profileRequest = URLRequest(url: profileUrl)
            profileRequest.httpMethod = "GET"
            profileRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            profileRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (profileData, profileResponse) = try await URLSession.shared.data(for: profileRequest)
            guard let profileHttpResponse = profileResponse as? HTTPURLResponse else {
                print("[AuthManager] Przerwano: Brak odpowiedzi HTTP dla profiles")
                return 
            }
            
            print("[AuthManager] Status odpowiedzi profiles: \(profileHttpResponse.statusCode)")
            let rawProfileJson = String(data: profileData, encoding: .utf8) ?? ""
            print("[AuthManager] Surowy JSON z tabeli profiles: \(rawProfileJson)")
            
            var finalJson: [[String: Any]]? = nil
            
            if (200...299).contains(profileHttpResponse.statusCode) {
                finalJson = try? JSONSerialization.jsonObject(with: profileData) as? [[String: Any]]
            } else {
                print("[AuthManager] Błąd podczas pobierania profiles (status: \(profileHttpResponse.statusCode)). Próba z Profiles (wielką)...")
                if let altProfileUrl = URL(string: "\(supabaseUrl)/rest/v1/Profiles?id=eq.\(userId)&select=*") {
                    var altRequest = URLRequest(url: altProfileUrl)
                    altRequest.httpMethod = "GET"
                    altRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                    altRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    if let (altData, altResp) = try? await URLSession.shared.data(for: altRequest),
                       let altHttpResp = altResp as? HTTPURLResponse {
                        print("[AuthManager] Status odpowiedzi Profiles (wielką): \(altHttpResp.statusCode)")
                        let rawAlt = String(data: altData, encoding: .utf8) ?? ""
                        print("[AuthManager] Surowy JSON z tabeli Profiles (wielką): \(rawAlt)")
                        if (200...299).contains(altHttpResp.statusCode) {
                            finalJson = try? JSONSerialization.jsonObject(with: altData) as? [[String: Any]]
                        }
                    }
                }
            }
            
            if let profiles = finalJson {
                print("[AuthManager] Otrzymano listę profili o rozmiarze: \(profiles.count)")
                if let profile = profiles.first {
                    print("[AuthManager] Zawartość pierwszego profilu: \(profile)")
                    
                    // Szukamy klucza created_at
                    if let createdAtValue = profile["created_at"] {
                        print("[AuthManager] Znaleziono wartość created_at: '\(createdAtValue)' (Typ: \(type(of: createdAtValue)))")
                        
                        if let createdAtStr = createdAtValue as? String {
                            print("[AuthManager] Próba parsowania daty z Supabase: '\(createdAtStr)'")
                            
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            
                            let formats = [
                                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
                                "yyyy-MM-dd'T'HH:mm:ss.SSSSSZZZZZ",
                                "yyyy-MM-dd'T'HH:mm:ss.SSSSZZZZZ",
                                "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
                                "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                                "yyyy-MM-dd HH:mm:ss.SSSSSSx",
                                "yyyy-MM-dd HH:mm:ss.SSSSSx",
                                "yyyy-MM-dd HH:mm:ss.SSSSx",
                                "yyyy-MM-dd HH:mm:ss.SSSx",
                                "yyyy-MM-dd HH:mm:ssx",
                                "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ",
                                "yyyy-MM-dd HH:mm:ss.SSSSSZZZZZ",
                                "yyyy-MM-dd HH:mm:ss.SSSZZZZZ",
                                "yyyy-MM-dd HH:mm:ssZZZZZ",
                                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSx",
                                "yyyy-MM-dd'T'HH:mm:ss.SSSSSx",
                                "yyyy-MM-dd'T'HH:mm:ss.SSSx",
                                "yyyy-MM-dd'T'HH:mm:ssx"
                            ]
                            
                            var date: Date? = nil
                            for format in formats {
                                formatter.dateFormat = format
                                if let d = formatter.date(from: createdAtStr) {
                                    date = d
                                    print("[AuthManager] Sukces! Dopasowano format '\(format)' -> \(d)")
                                    break
                                }
                            }
                            
                            if date == nil {
                                let isoFormatter = ISO8601DateFormatter()
                                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                date = isoFormatter.date(from: createdAtStr)
                                if date != nil {
                                    print("[AuthManager] Sukces! Dopasowano przez ISO8601DateFormatter (.withFractionalSeconds)")
                                }
                            }
                            
                            if date == nil {
                                let isoFormatter = ISO8601DateFormatter()
                                isoFormatter.formatOptions = [.withInternetDateTime]
                                date = isoFormatter.date(from: createdAtStr)
                                if date != nil {
                                    print("[AuthManager] Sukces! Dopasowano przez ISO8601DateFormatter (basic)")
                                }
                            }
                            
                            if let parsedDate = date {
                                print("[AuthManager] Ostateczna sparsowana data: \(parsedDate)")
                            } else {
                                print("[AuthManager] BŁĄD: Nie udało się dopasować żadnego formatu do daty '\(createdAtStr)'")
                            }
                            
                            let finalDate = date
                            await MainActor.run {
                                self.currentUserCreatedAt = finalDate
                            }
                        } else {
                            print("[AuthManager] Błąd: Wartość created_at nie jest typu String.")
                        }
                    } else {
                        print("[AuthManager] Błąd: Brak klucza 'created_at' w profilu! Dostępne klucze: \(profile.keys)")
                    }
                } else {
                    print("[AuthManager] Błąd: Lista profili jest pusta.")
                }
            } else {
                print("[AuthManager] Błąd: Słownik profiles (finalJson) jest nil.")
            }
        } catch {
            print("❌ Błąd pobierania danych profilu użytkownika: \(error)")
        }
    }
    
    private func extractErrorMessage(from data: Data) -> String {
        var errorMessage = "An unexpected server error occurred."
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = json["error_description"] as? String { errorMessage = msg }
            else if let msg = json["msg"] as? String { errorMessage = msg }
            else if let msg = json["message"] as? String { errorMessage = msg }
            else if let error = json["error"] as? String { errorMessage = error }
            else if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String { errorMessage = msg }
        } else if let rawString = String(data: data, encoding: .utf8), !rawString.isEmpty {
            errorMessage = rawString
        }
        
        return errorMessage
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
