import Foundation
import Security
import Combine
import AppKit

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isLoggedIn: Bool = false
    @Published var currentUserEmail: String? = nil
    @Published var currentUserCreatedAt: Date? = nil
    @Published var currentUserProvider: String = "email"
    @Published var accountDeletionError: String? = nil
    @Published var accountTier: String = "premium"
    var pendingAccountDeletion: Bool = false
    
    private let tokenKey = "sonor.supabase.access_token"
    private let emailKey = "sonor.supabase.user_email"
    
    private var supabaseUrl: String {
        return EnvReader.shared.getValue(for: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        return EnvReader.shared.getValue(for: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private var profileCacheURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sonorURL = appSupportURL.appendingPathComponent("Sonor", isDirectory: true)
        if !fileManager.fileExists(atPath: sonorURL.path) {
            try? fileManager.createDirectory(at: sonorURL, withIntermediateDirectories: true, attributes: nil)
        }
        return sonorURL.appendingPathComponent("profile_cache.json")
    }
    
    private func saveProfileCache(email: String, date: Date) {
        var cache: [String: Date] = [:]
        let url = profileCacheURL
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            cache = decoded
        }
        cache[email.lowercased()] = date
        if let encoded = try? JSONEncoder().encode(cache) {
            try? encoded.write(to: url, options: [.atomic])
            print("[AuthManager] Zapisano datę utworzenia profilu do cache dla \(email)")
        }
    }
    
    private func loadProfileCache(email: String) -> Date? {
        let url = profileCacheURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return nil
        }
        return decoded[email.lowercased()]
    }
    
    private func initProfileCacheFromLocalSession() {
        if let email = currentUserEmail {
            currentUserCreatedAt = loadProfileCache(email: email)
        }
    }
    
    private init() {
        checkLocalSession()
    }
    
    private func checkLocalSession() {
        if let token = getFromKeychain(key: tokenKey), !token.isEmpty {
            isLoggedIn = true
            let email = getFromKeychain(key: emailKey)
            currentUserEmail = email
            if let email = email {
                currentUserCreatedAt = loadProfileCache(email: email)
            }
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
        
        if (200...299).contains(httpResponse.statusCode) {
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
        
        if (200...299).contains(httpResponse.statusCode) {
            // Check if user already exists using the identities array trick
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let userObj = json["user"] as? [String: Any] ?? json
                if let identities = userObj["identities"] as? [[String: Any]], identities.isEmpty {
                    throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "User already registered"])
                }
            }
            // Rejestracja powiodła się. Wymagane potwierdzenie OTP.
            // Zwracamy bez błędu, a widok wyświetli okno potwierdzenia.
            return
        } else {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func checkEmailExists(email: String) async -> Bool {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else { return false }
        
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Try profiles table (lowercase)
        if let url = URL(string: "\(supabaseUrl)/rest/v1/profiles?email=eq.\(trimmedEmail)&select=id") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               !json.isEmpty {
                return true
            }
        }
        
        // Try Profiles table (uppercase)
        if let url = URL(string: "\(supabaseUrl)/rest/v1/Profiles?email=eq.\(trimmedEmail)&select=id") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               !json.isEmpty {
                return true
            }
        }
        
        return false
    }
    
    func verifyOTP(email: String, token: String) async throws {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase keys in .env file"])
        }
        
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/verify") else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["type": "signup", "email": email, "token": token]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        
        if (200...299).contains(httpResponse.statusCode) {
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
    
    func resendOTP(email: String) async throws {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase keys in .env file"])
        }
        
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/resend") else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["type": "signup", "email": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func requestPasswordChangeOTP(email: String) async throws {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase keys in .env file"])
        }
        
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/recover") else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["email": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func verifyPasswordChangeOTP(email: String, token: String) async throws {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase keys in .env file"])
        }
        
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/verify") else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["type": "recovery", "email": email, "token": token]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                
                // Save new recovery session
                saveToKeychain(key: tokenKey, value: accessToken)
                saveToKeychain(key: emailKey, value: email)
                
                self.isLoggedIn = true
                self.currentUserEmail = email
            }
        } else {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func loginWithGoogle() {
        guard !supabaseUrl.isEmpty else { return }
        if let url = URL(string: "\(supabaseUrl)/auth/v1/authorize?provider=google&redirect_to=sonor://auth-callback") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "sonor", url.host == "auth-callback" else { return }
        
        var queryItems = [String: String]()
        
        if let fragment = url.fragment {
            let pairs = fragment.components(separatedBy: "&")
            for pair in pairs {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    queryItems[kv[0]] = kv[1]
                }
            }
        }
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let qItems = components.queryItems {
            for item in qItems {
                if let val = item.value {
                    queryItems[item.name] = val
                }
            }
        }
        
        if let accessToken = queryItems["access_token"] {
            if self.pendingAccountDeletion {
                self.pendingAccountDeletion = false
                let oldEmailToVerify = self.currentUserEmail
                
                Task {
                    guard let userUrl = URL(string: "\(self.supabaseUrl)/auth/v1/user") else { return }
                    var userReq = URLRequest(url: userUrl)
                    userReq.addValue(self.supabaseAnonKey, forHTTPHeaderField: "apikey")
                    userReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    
                    if let (data, _) = try? await URLSession.shared.data(for: userReq),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let newEmail = json["email"] as? String {
                        
                        if newEmail.lowercased() == oldEmailToVerify?.lowercased() {
                            await MainActor.run {
                                self.saveToKeychain(key: self.tokenKey, value: accessToken)
                                self.isLoggedIn = true
                                self.accountDeletionError = nil
                            }
                            do {
                                try await self.deleteAccount()
                                await MainActor.run { self.logout() }
                            } catch {
                                let errMsg = error.localizedDescription
                                await MainActor.run {
                                    self.accountDeletionError = errMsg
                                }
                            }
                        } else {
                            print("[AuthManager] Błąd! Zalogowano na inne konto Google. Przerywam usuwanie.")
                            await MainActor.run {
                                self.accountDeletionError = "The selected Google account does not match. Please choose the correct account to delete it."
                            }
                        }
                    } else {
                        print("[AuthManager] Nie można zweryfikować e-maila w tokenie Google.")
                        await MainActor.run {
                            self.accountDeletionError = "Failed to verify the Google token. Please try again."
                        }
                    }
                }
            } else {
                saveToKeychain(key: tokenKey, value: accessToken)
                self.isLoggedIn = true
                Task {
                    await fetchUserDetails()
                }
            }
        }
    }
    
    func logout() {
        ModelManager.shared.pauseAllDownloads()
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: emailKey)
        self.isLoggedIn = false
        self.currentUserEmail = nil
        self.currentUserCreatedAt = nil
    }
    
    func deleteAccount() async throws {
        ModelManager.shared.pauseAllDownloads()
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
    
    func updatePassword(oldPassword: String, newPassword: String) async throws {
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
        
        let body: [String: Any] = ["password": newPassword, "current_password": oldPassword]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Brak odpowiedzi od serwera."])
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            print("[AuthManager] Hasło zostało pomyślnie zmienione.")
        } else {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func fetchUserDetails() async {
        print("[AuthManager] fetchUserDetails() rozpoczęte...")
        
        if let email = currentUserEmail, currentUserCreatedAt == nil {
            currentUserCreatedAt = loadProfileCache(email: email)
        }
        
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
                
                // Jeśli sesja wygasła (401 / 403), NIE wylogowujemy automatycznie.
                // Aplikacja jest offline-first, a brak obsługi refresh tokena powodował wylogowywanie co godzinę.
                if userHttpResponse.statusCode == 401 || userHttpResponse.statusCode == 403 {
                    print("[AuthManager] Sesja na serwerze wygasła (401/403). Zachowuję lokalną sesję zgodnie z prośbą użytkownika.")
                }
                return 
            }
            
            guard let userJson = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
                  let userId = userJson["id"] as? String else {
                print("[AuthManager] Przerwano: Nie udało się sparsować ID użytkownika z JSON.")
                return 
            }
            
            print("[AuthManager] Pobrano ID użytkownika: \(userId)")
            if let userEmail = userJson["email"] as? String {
                self.currentUserEmail = userEmail
                saveToKeychain(key: self.emailKey, value: userEmail)
            }
            if let appMetadata = userJson["app_metadata"] as? [String: Any],
               let provider = appMetadata["provider"] as? String {
                self.currentUserProvider = provider
            } else {
                self.currentUserProvider = "email"
            }
            
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
                    
                    // Parsing account_tier
                    if let tier = profile["account_tier"] as? String {
                        await MainActor.run { self.accountTier = tier }
                    }
                    
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
                                if let email = self.currentUserEmail, let finalDate = finalDate {
                                    self.saveProfileCache(email: email, date: finalDate)
                                    
                                    if self.currentUserProvider == "google" {
                                        let diff = abs(Date().timeIntervalSince(finalDate))
                                        if diff < 120 {
                                            NotificationCenter.default.post(name: Notification.Name("ShowThankYouView"), object: nil)
                                        }
                                    }
                                }
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
    
    func completeOnboarding() async {
        // Obsolete function since Onboarding is now local. 
        // We keep it as a no-op just in case it's called elsewhere, or we can just leave it empty.
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
        
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
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

import Network
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
