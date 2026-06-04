import SwiftUI
import Combine

class UserProfileViewModel: ObservableObject {
    @Published var showDeleteConfirmation = false
    @Published var showUnsubscribeConfirmation = false
    @Published var isUpdatingConsent = false
    @Published var localMarketingOptIn = false
    @Published var isDeleting = false
    @Published var deleteError: String? = nil
    @Published var deletePassword = ""
    
    @Published var isChangingPassword = false
    @Published var oldPassword = ""
    @Published var newPassword = ""
    @Published var confirmNewPassword = ""
    @Published var changePasswordError: String? = nil
    @Published var isSavingPassword = false
    @Published var showSuccessMessage = false
    
    @Published var isVerifyingOTPForPassword = false
    @Published var showSendEmailConfirmation = false
    @Published var otpDigits: [String] = Array(repeating: "\u{200B}", count: 6)
    @Published var oldOtpDigits: [String] = Array(repeating: "\u{200B}", count: 6)
    @Published var resendCooldown: Int = 60
    @Published var isLoadingOTP = false
    
    private var resendTimerTask: Task<Void, Never>? = nil
    
    var otpToken: String {
        otpDigits.joined().filter { $0.isNumber }
    }
    
    func formattedCreationDate(authManager: AuthManager, localizer: LocalizationManager) -> String {
        guard let date = authManager.currentUserCreatedAt else {
            return t("Loading...")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: localizer.appLanguage)
        return formatter.string(from: date)
    }
    
    func updateCooldown() {
        let lastSent = UserDefaults.standard.double(forKey: "lastPasswordOTPSentTime")
        let elapsed = Date().timeIntervalSince1970 - lastSent
        if elapsed < 60 {
            resendCooldown = Int(60 - elapsed)
        } else {
            resendCooldown = 0
            resendTimerTask?.cancel()
        }
    }
    
    func startResendTimer() {
        updateCooldown()
        resendTimerTask?.cancel()
        resendTimerTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    self.updateCooldown()
                }
                if resendCooldown <= 0 { break }
            }
        }
    }
    
    func resetOTPState() {
        otpDigits = Array(repeating: "\u{200B}", count: 6)
        oldOtpDigits = Array(repeating: "\u{200B}", count: 6)
    }
    
    func performPasswordChange(authManager: AuthManager, networkMonitor: NetworkMonitor) {
        if !networkMonitor.isConnected {
            changePasswordError = "Please connect to the internet to perform this action."
            return
        }
        let trimmedOld = oldPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmNewPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedOld.isEmpty { changePasswordError = "Please enter your old password."; return }
        if trimmedNew.isEmpty { changePasswordError = "Password cannot be empty."; return }
        if trimmedNew.count < 6 { changePasswordError = "Password must be at least 6 characters long."; return }
        if trimmedNew.rangeOfCharacter(from: .uppercaseLetters) == nil { changePasswordError = "Password must contain at least one uppercase letter."; return }
        if trimmedNew.rangeOfCharacter(from: .lowercaseLetters) == nil { changePasswordError = "Password must contain at least one lowercase letter."; return }
        if trimmedNew.rangeOfCharacter(from: .decimalDigits) == nil { changePasswordError = "Password must contain at least one number."; return }
        if trimmedNew == trimmedOld { changePasswordError = "New password cannot be the same as the old password."; return }
        if trimmedNew != trimmedConfirm { changePasswordError = "Passwords do not match."; return }
        
        isSavingPassword = true
        changePasswordError = nil
        Task {
            do {
                if let email = authManager.currentUserEmail {
                    do {
                        try await authManager.login(email: email, password: trimmedOld)
                    } catch {
                        let errStr = error.localizedDescription
                        if errStr.lowercased().contains("invalid login credentials") || errStr.lowercased().contains("invalid credentials") {
                            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Incorrect old password."])
                        } else {
                            throw error
                        }
                    }
                }
                try await authManager.updatePassword(oldPassword: trimmedOld, newPassword: trimmedNew)
                await MainActor.run {
                    isSavingPassword = false
                    oldPassword = ""
                    newPassword = ""
                    confirmNewPassword = ""
                    withAnimation {
                        showSuccessMessage = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingPassword = false
                    changePasswordError = error.localizedDescription
                }
            }
        }
    }
    
    func performAccountDeletion(authManager: AuthManager, networkMonitor: NetworkMonitor, dismiss: DismissAction) {
        if !networkMonitor.isConnected {
            deleteError = "Please connect to the internet to perform this action."
            return
        }
        if authManager.currentUserProvider == "google" {
            deleteError = nil
            isDeleting = true
            authManager.accountDeletionError = nil
            authManager.pendingAccountDeletion = true
            authManager.loginWithGoogle()
            return
        }
        guard !deletePassword.isEmpty else {
            deleteError = "Password cannot be empty."
            return
        }
        isDeleting = true
        deleteError = nil
        let passwordToVerify = deletePassword
        Task {
            do {
                if let email = authManager.currentUserEmail {
                    try await authManager.login(email: email, password: passwordToVerify)
                }
                try await authManager.deleteAccount()
                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = error.localizedDescription
                }
            }
        }
    }
    
    func updateMarketingConsent(authManager: AuthManager, networkMonitor: NetworkMonitor, newValue: Bool) {
        if !networkMonitor.isConnected {
            deleteError = "Please connect to the internet to perform this action."
            localMarketingOptIn = !newValue
            return
        }
        isUpdatingConsent = true
        deleteError = nil
        Task {
            do {
                try await authManager.updateMarketingOptIn(newValue: newValue)
                await MainActor.run {
                    isUpdatingConsent = false
                }
            } catch {
                await MainActor.run {
                    isUpdatingConsent = false
                    deleteError = error.localizedDescription
                    localMarketingOptIn = !newValue
                }
            }
        }
    }
    
    func cancelTimer() {
        resendTimerTask?.cancel()
    }
}
