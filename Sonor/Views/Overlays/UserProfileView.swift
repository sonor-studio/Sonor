import SwiftUI

struct UserProfileView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appTheme") private var appTheme = "system"
    var colorScheme: ColorScheme {
        if appTheme == "dark" {
            return .dark
        } else if appTheme == "light" {
            return .light
        } else {
            let appleInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            return appleInterfaceStyle == "Dark" ? .dark : .light
        }
    }
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var localizer = LocalizationManager.shared
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    
    @State private var isCloseHovered = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil
    @State private var deletePassword = ""
    @FocusState private var isDeleteFieldFocused: Bool
    
    // Change Password States
    @State private var isChangingPassword = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var changePasswordError: String? = nil
    @State private var isSavingPassword = false
    @State private var showSuccessMessage = false
    
    // OTP States for Password Change
    @State private var isVerifyingOTPForPassword = false
    @State private var showSendEmailConfirmation = false
    @State private var otpDigits: [String] = Array(repeating: "\u{200B}", count: 6)
    @State private var oldOtpDigits: [String] = Array(repeating: "\u{200B}", count: 6)
    @FocusState private var focusedField: Int?
    @State private var resendCooldown: Int = 60
    @State private var resendTimerTask: Task<Void, Never>? = nil
    @State private var isLoadingOTP = false
    
    private func updateCooldown() {
        let lastSent = UserDefaults.standard.double(forKey: "lastPasswordOTPSentTime")
        let elapsed = Date().timeIntervalSince1970 - lastSent
        if elapsed < 60 {
            resendCooldown = Int(60 - elapsed)
        } else {
            resendCooldown = 0
            resendTimerTask?.cancel()
        }
    }
    
    private func startResendTimer() {
        updateCooldown()
        resendTimerTask?.cancel()
        resendTimerTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    updateCooldown()
                }
                if resendCooldown <= 0 { break }
            }
        }
    }
    
    
    private var otpToken: String {
        otpDigits.joined().filter { $0.isNumber }
    }
    
    private var formattedCreationDate: String {
        guard let date = authManager.currentUserCreatedAt else {
            return t("Loading...")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: localizer.appLanguage)
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with custom close button
            HStack {
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isCloseHovered ? (colorScheme == .dark ? .white : .black) : .secondary)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                    .onTapGesture {
                        dismiss()
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            if showSuccessMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text(t("Password Updated Successfully!"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(t("Your account is now secure with the new password."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .transition(.opacity)
                .onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            withAnimation {
                                showSuccessMessage = false
                                isChangingPassword = false
                                 otpDigits = Array(repeating: "\u{200B}", count: 6)
                                 oldOtpDigits = Array(repeating: "\u{200B}", count: 6)
                            }
                        }
                    }
                }
            } else if showSendEmailConfirmation {
                VStack(spacing: 14) {
                    Text(t("Confirm Email"))
                        .font(.system(size: 20, weight: .bold))
                        .padding(.top, 10)
                    
                    Text(t("To continue, you need to confirm your email address. We will send a 6-digit code to your email."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                    
                    if let error = changePasswordError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 13, weight: .medium))
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 40)
                    }
                    
                    Button(action: {
                        Task {
                            isLoadingOTP = true
                            changePasswordError = nil
                            do {
                                if let email = authManager.currentUserEmail {
                                    try await authManager.requestPasswordChangeOTP(email: email)
                                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPasswordOTPSentTime")
                                    startResendTimer()
                                    withAnimation {
                                        showSendEmailConfirmation = false
                                        isVerifyingOTPForPassword = true
                                    }
                                }
                            } catch {
                                changePasswordError = tError(error.localizedDescription)
                            }
                            isLoadingOTP = false
                        }
                    }) {
                        HStack {
                            if isLoadingOTP {
                                ProgressView().controlSize(.small)
                                    .padding(.trailing, 5)
                            }
                            Text(t("Confirm email"))
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 40)
                    .disabled(isLoadingOTP)
                    .keyboardShortcut(.defaultAction)
                    
                    Button(action: {
                        withAnimation {
                            showSendEmailConfirmation = false
                            changePasswordError = nil
                        }
                    }) {
                        Text(t("Cancel"))
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if isVerifyingOTPForPassword {
                VStack(spacing: 14) {
                    Text(t("Confirm Email"))
                        .font(.system(size: 20, weight: .bold))
                        .padding(.top, 10)
                    
                    Text(t("Please enter the 6-character confirmation code sent to your email."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 4)
                    
                    if let error = changePasswordError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 13, weight: .medium))
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 40)
                    }
                    
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            TextField("", text: $otpDigits[index])
                                .textFieldStyle(.plain)
                                .font(.system(size: 24, weight: .bold))
                                .multilineTextAlignment(.center)
                                .frame(width: 40, height: 50)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(focusedField == index ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .focused($focusedField, equals: index)
                                .onChange(of: otpDigits[index]) { newValue in
                                    let oldVal = oldOtpDigits[index]
                                    let filtered = newValue.filter { $0.isNumber }
                                    
                                    if filtered.isEmpty {
                                        if newValue == "" {
                                            // USER PRESSED BACKSPACE
                                            otpDigits[index] = "\u{200B}"
                                            oldOtpDigits[index] = "\u{200B}"
                                            if index > 0 {
                                                focusedField = index - 1
                                            }
                                        } else if newValue == "\u{200B}" {
                                            // Recursive call after setting "\u{200B}"
                                            oldOtpDigits[index] = "\u{200B}"
                                        } else {
                                            // WPISANO LITERĘ
                                            // Odrzucamy literę, wracamy do poprzedniej wartości bez zmiany fokusu
                                            otpDigits[index] = oldVal
                                        }
                                        return
                                    }
                                    
                                    // Wpisano lub wklejono więcej cyfr
                                    if filtered.count > 1 {
                                        let chars = Array(filtered.prefix(6))
                                        for i in 0..<chars.count {
                                            if index + i < 6 {
                                                otpDigits[index + i] = String(chars[i])
                                                oldOtpDigits[index + i] = String(chars[i])
                                            }
                                        }
                                        focusedField = min(index + chars.count, 5)
                                    } else { // filtered.count == 1
                                        otpDigits[index] = filtered
                                        oldOtpDigits[index] = filtered
                                        
                                        if oldVal != filtered {
                                            if index < 5 {
                                                focusedField = index + 1
                                            }
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                    .onChange(of: focusedField) { newValue in
                        if let newIndex = newValue {
                            let firstEmpty = otpDigits.firstIndex(where: { $0 == "\u{200B}" || $0.isEmpty }) ?? 5
                            if newIndex > firstEmpty {
                                focusedField = firstEmpty
                            }
                        }
                    }
                    .onAppear {
                        focusedField = 0
                        updateCooldown()
                        startResendTimer()
                    }
                    
                    Button(action: {
                        Task {
                            isLoadingOTP = true
                            changePasswordError = nil
                            do {
                                if let email = authManager.currentUserEmail {
                                    try await authManager.verifyPasswordChangeOTP(email: email, token: otpToken)
                                    // OTP Verified!
                                    UserDefaults.standard.set(0.0, forKey: "lastPasswordOTPSentTime")
                                    withAnimation {
                                        isVerifyingOTPForPassword = false
                                        isChangingPassword = true
                                    }
                                }
                            } catch {
                                changePasswordError = tError(error.localizedDescription)
                            }
                            isLoadingOTP = false
                        }
                    }) {
                        HStack {
                            if isLoadingOTP {
                                ProgressView().controlSize(.small)
                                    .padding(.trailing, 5)
                            }
                            Text(t("Verify"))
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 40)
                    .disabled(isLoadingOTP || otpToken.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    
                    Button(action: {
                        Task {
                            isLoadingOTP = true
                            let lastSent = UserDefaults.standard.double(forKey: "lastPasswordOTPSentTime")
                            let elapsed = Date().timeIntervalSince1970 - lastSent
                            if elapsed >= 60 {
                                do {
                                    if let email = authManager.currentUserEmail {
                                        try await authManager.requestPasswordChangeOTP(email: email)
                                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPasswordOTPSentTime")
                                        startResendTimer()
                                        changePasswordError = nil
                                    }
                                } catch {
                                    changePasswordError = tError(error.localizedDescription)
                                }
                            } else {
                                if resendCooldown == 0 {
                                    resendCooldown = Int(60 - elapsed)
                                    startResendTimer()
                                }
                            }
                            isLoadingOTP = false
                        }
                    }) {
                        Text(resendCooldown > 0 ? t("Resend Email") + " (\(resendCooldown)s)" : t("Resend Email"))
                            .font(.system(size: 13))
                            .foregroundColor(resendCooldown > 0 ? .secondary : .primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .disabled(resendCooldown > 0 || isLoadingOTP)
                    
                    Button(action: {
                        withAnimation {
                            isVerifyingOTPForPassword = false
                            showSendEmailConfirmation = false
                            changePasswordError = nil
                            otpDigits = Array(repeating: "\u{200B}", count: 6)
                            oldOtpDigits = Array(repeating: "\u{200B}", count: 6)
                        }
                    }) {
                        Text(t("Cancel"))
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    
                    Spacer()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if isChangingPassword {
                VStack(spacing: 14) {
                    Text(t("Change Password"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        
                    if let error = changePasswordError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 13, weight: .medium))
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 24)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Old password"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        SecureField(t("Enter old password..."), text: $oldPassword)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .cornerRadius(8)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("New password"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        SecureField(t("Enter new password..."), text: $newPassword)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .cornerRadius(8)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Repeat new password"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        SecureField(t("Repeat new password..."), text: $confirmNewPassword)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .cornerRadius(8)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 24)
                    
                            // Error message removed from here
                    
                    Spacer()
                    
                    if isSavingPassword {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 20)
                    } else {
                        // Save Button
                        Button(action: {
                            performPasswordChange()
                        }) {
                            Text(t("Save Password"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colorScheme == .dark ? Color.white : Color.black)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.horizontal, 24)
                        .keyboardShortcut(.defaultAction)
                        
                        // Cancel Button
                        Button(action: {
                            withAnimation {
                                isChangingPassword = false
                                oldPassword = ""
                                newPassword = ""
                                confirmNewPassword = ""
                                changePasswordError = nil
                                otpDigits = Array(repeating: "\u{200B}", count: 6)
                                oldOtpDigits = Array(repeating: "\u{200B}", count: 6)
                            }
                        }) {
                            Text(t("Cancel"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    // Avatar
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    
                    // Dynamic subscription tag if logged in
                    Text(t(authManager.accountTier.uppercased()))
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(4)
                        .padding(.bottom, 16)
                    
                    // Email and date
                    VStack(spacing: 6) {
                        Text(authManager.currentUserEmail ?? "")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("\(t("Member since:")) \(formattedCreationDate)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 30)
                    
                    Spacer()
                    
                    // Log Out Button
                    Button(action: {
                        authManager.logout()
                        dismiss()
                    }) {
                        Text(t("Log Out"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(colorScheme == .dark ? Color.white : Color.black)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    
                    // Change Password Button
                    if authManager.currentUserProvider != "google" {
                        Button(action: {
                            if !networkMonitor.isConnected {
                                deleteError = t("Please connect to the internet to perform this action.")
                                return
                            }
                            deleteError = nil
                            let lastSent = UserDefaults.standard.double(forKey: "lastPasswordOTPSentTime")
                            let elapsed = Date().timeIntervalSince1970 - lastSent
                            
                            if elapsed < 60 {
                                resendCooldown = Int(60 - elapsed)
                            } else {
                                resendCooldown = 0
                            }
                            
                            if elapsed >= 60 {
                                withAnimation {
                                    showSendEmailConfirmation = true
                                }
                            } else {
                                withAnimation {
                                    isVerifyingOTPForPassword = true
                                }
                                startResendTimer()
                            }
                        }) {
                            Text(t("Change Password"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    }
                    
                    // Delete Account Button
                    Button(action: {
                        if !networkMonitor.isConnected {
                            deleteError = t("Please connect to the internet to perform this action.")
                            return
                        }
                        deleteError = nil
                        showDeleteConfirmation = true
                        triggerDeleteAccountFocus()
                    }) {
                        Text(t("Delete Account"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    
                    if let deleteError = deleteError {
                        Text(deleteError)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)
                    }
                    
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 10)
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 400, height: 550) // Adjust height to support three password fields cleanly
        .background(colorScheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.05) : Color.white)
        .foregroundColor(.primary)
        .alert(t("Delete Account"), isPresented: $showDeleteConfirmation) {
            if authManager.currentUserProvider == "google" {
                Button(t("Delete"), role: .destructive) {
                    performAccountDeletion()
                }
                Button(t("Cancel"), role: .cancel) {}
            } else {
                SecureField(t("Password"), text: $deletePassword)
                    .focused($isDeleteFieldFocused)
                    .onSubmit {
                        performAccountDeletion()
                    }
                Button(t("Delete"), role: .destructive) {
                    performAccountDeletion()
                }
                Button(t("Cancel"), role: .cancel) {
                    deletePassword = ""
                }
            }
        } message: {
            if authManager.currentUserProvider == "google" {
                Text(t("You will be redirected to Google to authorize the deletion of your account. This action cannot be undone."))
            } else {
                Text(t("Please enter your password to confirm. This action cannot be undone."))
            }
        }
        .task {
            authManager.accountDeletionError = nil
            await authManager.fetchUserDetails()
        }
        .onDisappear {
            resendTimerTask?.cancel()
        }
        .onChange(of: showDeleteConfirmation) { newValue in
            if newValue {
                triggerDeleteAccountFocus()
            }
        }
        .onChange(of: authManager.isLoggedIn) { newValue in
            if !newValue {
                dismiss()
            }
        }
        .onChange(of: authManager.accountDeletionError) { newValue in
            if let error = newValue {
                deleteError = t(error)
                isDeleting = false
            }
        }
    }
    
    private func triggerDeleteAccountFocus() {
        isDeleteFieldFocused = true
        for delay in [0.05, 0.1, 0.15, 0.2, 0.3, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if showDeleteConfirmation {
                    isDeleteFieldFocused = true
                }
            }
        }
    }
    
    private func performPasswordChange() {
        if !networkMonitor.isConnected {
            changePasswordError = t("Please connect to the internet to perform this action.")
            return
        }
        
        let trimmedOld = oldPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmNewPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedOld.isEmpty {
            changePasswordError = t("Please enter your old password.")
            return
        }
        
        if trimmedNew.isEmpty {
            changePasswordError = t("Password cannot be empty.")
            return
        }
        
        if trimmedNew.count < 6 {
            changePasswordError = t("Password must be at least 6 characters long.")
            return
        }
        
        if trimmedNew.rangeOfCharacter(from: .uppercaseLetters) == nil {
            changePasswordError = t("Password must contain at least one uppercase letter.")
            return
        }
        
        if trimmedNew.rangeOfCharacter(from: .lowercaseLetters) == nil {
            changePasswordError = t("Password must contain at least one lowercase letter.")
            return
        }
        
        if trimmedNew.rangeOfCharacter(from: .decimalDigits) == nil {
            changePasswordError = t("Password must contain at least one number.")
            return
        }
        
        if trimmedNew == trimmedOld {
            changePasswordError = t("New password cannot be the same as the old password.")
            return
        }
        
        if trimmedNew != trimmedConfirm {
            changePasswordError = t("Passwords do not match.")
            return
        }
        
        isSavingPassword = true
        changePasswordError = nil
        
        Task {
            do {
                // Verify old password by logging in again
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
                
                // If login succeeds, update password
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
                    changePasswordError = tError(error.localizedDescription)
                }
            }
        }
    }
    
    private func performAccountDeletion() {
        if !networkMonitor.isConnected {
            deleteError = t("Please connect to the internet to perform this action.")
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
            deleteError = t("Password cannot be empty.")
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
                    deleteError = tError(error.localizedDescription)
                }
            }
        }
    }
}
