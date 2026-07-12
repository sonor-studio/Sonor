import Foundation
import Security
import Combine
import AppKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    @Published var isLoggedIn: Bool = false
    @Published var currentUserEmail: String? = nil
    @Published var currentUserCreatedAt: Date? = nil
    @Published var currentUserProvider: String = "email"
    @Published var accountDeletionError: String? = nil
    @Published var accountTier: String = "premium"
    @Published var marketingOptIn: Bool = false
    var pendingAccountDeletion: Bool = false
    private let tokenKey = "sonor.supabase.access_token"
    private let refreshTokenKey = "sonor.supabase.refresh_token"
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
            Task {
                await fetchUserDetails()
            }
        } else {
            isLoggedIn = false
            currentUserEmail = nil
            currentUserCreatedAt = nil
        }
    }
    private func isTokenExpired(_ token: String) -> Bool {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return true }
        let payloadPart = parts[1]
        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let length = base64.count
        let requiredLength = Int(ceil(Double(length) / 4.0) * 4.0)
        let padding = requiredLength - length
        if padding > 0 {
            base64 += String(repeating: "=", count: padding)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }
        let expiryDate = Date(timeIntervalSince1970: exp)
        return expiryDate.compare(Date().addingTimeInterval(60)) == .orderedAscending
    }
    func getValidAccessToken() async throws -> String {
        guard let token = getFromKeychain(key: tokenKey), !token.isEmpty else {
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Brak tokenu. Zaloguj się ponownie."])
        }
        if isTokenExpired(token) {
            return try await refreshSession()
        }
        return token
    }
    @discardableResult
    func refreshSession() async throws -> String {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase keys in .env file"])
        }
        guard let refreshToken = getFromKeychain(key: refreshTokenKey), !refreshToken.isEmpty else {
            await MainActor.run { logout() }
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Brak tokenu odświeżania. Zaloguj się ponownie."])
        }
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/token?grant_type=refresh_token") else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        if (200...299).contains(httpResponse.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newAccessToken = json["access_token"] as? String,
               let newRefreshToken = json["refresh_token"] as? String {
                await MainActor.run {
                    self.saveToKeychain(key: self.tokenKey, value: newAccessToken)
                    self.saveToKeychain(key: self.refreshTokenKey, value: newRefreshToken)
                    self.isLoggedIn = true
                }
                return newAccessToken
            } else {
                throw NSError(domain: "AuthError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Error parsing token response"])
            }
        } else {
            let errorMsg = extractErrorMessage(from: data)
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                await MainActor.run { logout() }
            }
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
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
                saveToKeychain(key: tokenKey, value: accessToken)
                if let refreshToken = json["refresh_token"] as? String {
                    saveToKeychain(key: refreshTokenKey, value: refreshToken)
                }
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
    func register(email: String, password: String, marketingOptIn: Bool) async throws {
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
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "data": [
                "marketing_opt_in": marketingOptIn
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid response from server"])
        }
        if (200...299).contains(httpResponse.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let userObj = json["user"] as? [String: Any] ?? json
                if let identities = userObj["identities"] as? [[String: Any]], identities.isEmpty {
                    throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "User already registered"])
                }
            }
            return
        } else {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    func checkEmailExists(email: String) async -> Bool {
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else { return false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                saveToKeychain(key: tokenKey, value: accessToken)
                if let refreshToken = json["refresh_token"] as? String {
                    saveToKeychain(key: refreshTokenKey, value: refreshToken)
                }
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
                saveToKeychain(key: tokenKey, value: accessToken)
                if let refreshToken = json["refresh_token"] as? String {
                    saveToKeychain(key: refreshTokenKey, value: refreshToken)
                }
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
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
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
            let refreshToken = queryItems["refresh_token"]
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
                                if let refreshToken = refreshToken {
                                    self.saveToKeychain(key: self.refreshTokenKey, value: refreshToken)
                                }
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
                            await MainActor.run {
                                self.accountDeletionError = "The selected Google account does not match. Please choose the correct account to delete it."
                            }
                        }
                    } else {
                        await MainActor.run {
                            self.accountDeletionError = "Failed to verify the Google token. Please try again."
                        }
                    }
                }
            } else {
                saveToKeychain(key: tokenKey, value: accessToken)
                if let refreshToken = refreshToken {
                    saveToKeychain(key: refreshTokenKey, value: refreshToken)
                }
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
        deleteFromKeychain(key: refreshTokenKey)
        deleteFromKeychain(key: emailKey)
        self.isLoggedIn = false
        self.currentUserEmail = nil
        self.currentUserCreatedAt = nil
        self.marketingOptIn = false
    }
    func deleteAccount() async throws {
        ModelManager.shared.pauseAllDownloads()
        let token = try await getValidAccessToken()
        guard let userUrl = URL(string: "\(supabaseUrl)/auth/v1/user") else { throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "URL Error."]) }
        var userReq = URLRequest(url: userUrl)
        userReq.httpMethod = "GET"
        userReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        userReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (uData, uResp) = try await URLSession.shared.data(for: userReq)
        if let uHttp = uResp as? HTTPURLResponse, uHttp.statusCode == 200,
           let uJson = try? JSONSerialization.jsonObject(with: uData) as? [String: Any],
           let userId = uJson["id"] as? String {
            if let profUrl = URL(string: "\(supabaseUrl)/rest/v1/profiles?id=eq.\(userId)") {
                var pReq = URLRequest(url: profUrl)
                pReq.httpMethod = "DELETE"
                pReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                pReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (_, _) = try await URLSession.shared.data(for: pReq)
            }
        }
        guard let rpcUrl = URL(string: "\(supabaseUrl)/rest/v1/rpc/delete_own_user") else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "RPC URL Error."])
        }
        var rpcReq = URLRequest(url: rpcUrl)
        rpcReq.httpMethod = "POST"
        rpcReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        rpcReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (rData, rResp) = try await URLSession.shared.data(for: rpcReq)
        guard let rHttp = rResp as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Brak odpowiedzi od serwera."])
        }
        if (200...299).contains(rHttp.statusCode) {
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
        let token = try await getValidAccessToken()
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/user") else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "URL Error."])
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
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    func updatePasswordAfterRecovery(newPassword: String) async throws {
        let token = try await getValidAccessToken()
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/user") else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "URL Error."])
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
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = extractErrorMessage(from: data)
            throw NSError(domain: "AuthError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    func updateMarketingOptIn(newValue: Bool) async throws {
        let token = try await getValidAccessToken()
        guard let userUrl = URL(string: "\(supabaseUrl)/auth/v1/user") else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "URL Error."])
        }
        var userReq = URLRequest(url: userUrl)
        userReq.httpMethod = "GET"
        userReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        userReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (uData, uResp) = try await URLSession.shared.data(for: userReq)
        guard let uHttp = uResp as? HTTPURLResponse, uHttp.statusCode == 200,
           let uJson = try? JSONSerialization.jsonObject(with: uData) as? [String: Any],
           let userId = uJson["id"] as? String else {
            throw NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error fetching user ID."])
        }
        guard let profUrl = URL(string: "\(supabaseUrl)/rest/v1/profiles?id=eq.\(userId)") else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Profiles URL Error."])
        }
        var pReq = URLRequest(url: profUrl)
        pReq.httpMethod = "PATCH"
        pReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        pReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        pReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["marketing_opt_in": newValue]
        pReq.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (pData, pResp) = try await URLSession.shared.data(for: pReq)
        guard let pHttp = pResp as? HTTPURLResponse else {
            throw NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Brak odpowiedzi od serwera."])
        }
        if (200...299).contains(pHttp.statusCode) {
            await MainActor.run {
                self.marketingOptIn = newValue
            }
        } else {
            guard let altProfUrl = URL(string: "\(supabaseUrl)/rest/v1/Profiles?id=eq.\(userId)") else {
                let errorMsg = extractErrorMessage(from: pData)
                throw NSError(domain: "AuthError", code: pHttp.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            var altReq = URLRequest(url: altProfUrl)
            altReq.httpMethod = "PATCH"
            altReq.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            altReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            altReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
            altReq.httpBody = pReq.httpBody
            let (altData, altResp) = try await URLSession.shared.data(for: altReq)
            guard let altHttp = altResp as? HTTPURLResponse else {
                throw NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Brak odpowiedzi od serwera dla Profiles."])
            }
            if (200...299).contains(altHttp.statusCode) {
                await MainActor.run {
                    self.marketingOptIn = newValue
                }
            } else {
                let errorMsg = extractErrorMessage(from: altData)
                throw NSError(domain: "AuthError", code: altHttp.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }
    }
    func fetchUserDetails() async {
        if let email = currentUserEmail, currentUserCreatedAt == nil {
            currentUserCreatedAt = loadProfileCache(email: email)
        }
        let token: String
        do {
            token = try await getValidAccessToken()
        } catch {
            return
        }
        guard !supabaseUrl.isEmpty, !supabaseAnonKey.isEmpty else {
            return 
        }
        guard let userUrl = URL(string: "\(supabaseUrl)/auth/v1/user") else { 
            return 
        }
        var userRequest = URLRequest(url: userUrl)
        userRequest.httpMethod = "GET"
        userRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        userRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (userData, userResponse) = try await URLSession.shared.data(for: userRequest)
            guard let userHttpResponse = userResponse as? HTTPURLResponse else {
                return
            }
            guard (200...299).contains(userHttpResponse.statusCode) else {
                return 
            }
            guard let userJson = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
                  let userId = userJson["id"] as? String else {
                return 
            }
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
            guard let profileUrl = URL(string: "\(supabaseUrl)/rest/v1/profiles?id=eq.\(userId)&select=*") else { 
                return 
            }
            var profileRequest = URLRequest(url: profileUrl)
            profileRequest.httpMethod = "GET"
            profileRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            profileRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (profileData, profileResponse) = try await URLSession.shared.data(for: profileRequest)
            guard let profileHttpResponse = profileResponse as? HTTPURLResponse else {
                return 
            }
            var finalJson: [[String: Any]]? = nil
            if (200...299).contains(profileHttpResponse.statusCode) {
                finalJson = try? JSONSerialization.jsonObject(with: profileData) as? [[String: Any]]
            } else {
                if let altProfileUrl = URL(string: "\(supabaseUrl)/rest/v1/Profiles?id=eq.\(userId)&select=*") {
                    var altRequest = URLRequest(url: altProfileUrl)
                    altRequest.httpMethod = "GET"
                    altRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                    altRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    if let (altData, altResp) = try? await URLSession.shared.data(for: altRequest),
                       let altHttpResp = altResp as? HTTPURLResponse {
                        if (200...299).contains(altHttpResp.statusCode) {
                            finalJson = try? JSONSerialization.jsonObject(with: altData) as? [[String: Any]]
                        }
                    }
                }
            }
            if let profiles = finalJson {
                if let profile = profiles.first {
                    if let tier = profile["account_tier"] as? String {
                        await MainActor.run { self.accountTier = tier }
                    }
                    if let optInVal = profile["marketing_opt_in"] {
                        var optIn = false
                        if let b = optInVal as? Bool {
                            optIn = b
                        } else if let num = optInVal as? NSNumber {
                            optIn = num.boolValue
                        } else if let s = optInVal as? String {
                            optIn = (s.lowercased() == "true" || s == "1")
                        }
                        await MainActor.run { self.marketingOptIn = optIn }
                    }
                    if let createdAtValue = profile["created_at"] {
                        if let createdAtStr = createdAtValue as? String {
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
                                    break
                                }
                            }
                            if date == nil {
                                let isoFormatter = ISO8601DateFormatter()
                                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                date = isoFormatter.date(from: createdAtStr)
                            }
                            if date == nil {
                                let isoFormatter = ISO8601DateFormatter()
                                isoFormatter.formatOptions = [.withInternetDateTime]
                                date = isoFormatter.date(from: createdAtStr)
                            }
                            let finalDate = date
                            await MainActor.run {
                                self.currentUserCreatedAt = finalDate
                                if let email = self.currentUserEmail, let finalDate = finalDate {
                                    self.saveProfileCache(email: email, date: finalDate)
                                    if self.currentUserProvider == "google" {
                                        let diff = abs(Date().timeIntervalSince(finalDate))
                                        let defaultsKey = "hasShownThankYou_\(email)"
                                        if diff < 120 && !UserDefaults.standard.bool(forKey: defaultsKey) {
                                            UserDefaults.standard.set(true, forKey: defaultsKey)
                                            NotificationCenter.default.post(name: Notification.Name("ShowThankYouView"), object: nil)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            // Ignore fetch errors
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
