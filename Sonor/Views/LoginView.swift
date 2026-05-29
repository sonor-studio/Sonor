import SwiftUI

struct LoginView: View {
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
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var localizer = LocalizationManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isRegistering = false
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var acceptedPrivacyPolicy = false
    @State private var showOTPVerification = false
    @State private var otpDigits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedField: Int?
    @State private var resendCooldown: Int = 60
    @State private var resendTimerTask: Task<Void, Never>? = nil
    
    private func startResendTimer() {
        resendCooldown = 60
        resendTimerTask?.cancel()
        resendTimerTask = Task {
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    resendCooldown -= 1
                }
            }
        }
    }
    
    private func binding(for index: Int) -> Binding<String> {
        Binding<String>(
            get: {
                let val = self.otpDigits[index]
                return val.isEmpty ? "\u{200B}" : val
            },
            set: { newValue in
                let oldVal = self.otpDigits[index]
                let filtered = newValue.filter { $0.isNumber }
                
                if filtered.count > 1 {
                    let chars = Array(filtered.prefix(6))
                    for i in 0..<chars.count {
                        self.otpDigits[i] = String(chars[i])
                    }
                    self.focusedField = min(chars.count, 5)
                } else if filtered.count == 1 {
                    self.otpDigits[index] = filtered
                    if index < 5 { self.focusedField = index + 1 }
                } else {
                    if newValue == "" {
                        if oldVal.isEmpty {
                            if index > 0 {
                                self.focusedField = index - 1
                                self.otpDigits[index - 1] = ""
                            }
                        } else {
                            self.otpDigits[index] = ""
                            if index > 0 {
                                self.focusedField = index - 1
                            }
                        }
                    } else {
                        self.otpDigits[index] = ""
                    }
                }
            }
        )
    }
    
    private var otpToken: String {
        otpDigits.joined()
    }
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundColor(.primary)
            
            if showOTPVerification {
                Text(t("Confirm Email"))
                    .font(.system(size: 20, weight: .bold))
                
                Text(t("Please enter the 6-character confirmation code sent to your email."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 4)
                
                if let error = errorMessage {
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
                        TextField("", text: binding(for: index))
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
                    }
                }
                .padding(.vertical, 8)
                .onChange(of: focusedField) { newValue in
                    if let newIndex = newValue {
                        let firstEmpty = otpDigits.firstIndex(where: { $0.isEmpty }) ?? 5
                        if newIndex > firstEmpty {
                            focusedField = firstEmpty
                        }
                    }
                }
                .onAppear {
                    focusedField = 0
                }
                
                Button(action: {
                    Task {
                        await handleOTPVerification()
                    }
                }) {
                    HStack {
                        if isLoading {
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
                .disabled(isLoading || otpToken.isEmpty)
                
                Button(action: {
                    Task {
                        isLoading = true
                        do {
                            try await authManager.resendOTP(email: email)
                            startResendTimer()
                            errorMessage = nil
                        } catch {
                            errorMessage = tError(error.localizedDescription)
                        }
                        isLoading = false
                    }
                }) {
                    Text(resendCooldown > 0 ? t("Resend Email") + " (\(resendCooldown)s)" : t("Resend Email"))
                        .font(.system(size: 13))
                        .foregroundColor(resendCooldown > 0 ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .disabled(resendCooldown > 0 || isLoading)
                
                Button(action: {
                    withAnimation {
                        showOTPVerification = false
                        errorMessage = nil
                    }
                }) {
                    Text(t("Back"))
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                Text(isRegistering ? t("Join Sonor") : t("Welcome Back"))
                    .font(.system(size: 20, weight: .bold))
            
            Text(t("Unlock advanced AI assistants, intelligent dictionaries, and custom snippets to turn every recording into polished text. Everything is 100% free and runs fully offline on your computer — your data is completely private, and we do not collect any information."))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 4)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 13, weight: .medium))
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 10) {
                TextField(t("Email address"), text: $email)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                
                SecureField(t("Password"), text: $password)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    
                if isRegistering {
                    SecureField(t("Repeat password"), text: $confirmPassword)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        
                    HStack(spacing: 8) {
                        Toggle("", isOn: $acceptedPrivacyPolicy)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accentColor(colorScheme == .dark ? .white : .black)
                            .tint(colorScheme == .dark ? .white : .black)
                        
                        HStack(spacing: 4) {
                            let prefix = t("I accept the")
                            if !prefix.isEmpty {
                                Text(prefix)
                                    .font(.system(size: 13))
                            }
                            
                            Button(action: {
                                openPrivacyPolicy()
                            }) {
                                Text(t("Privacy Policy"))
                                    .font(.system(size: 13))
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text(t("and"))
                                .font(.system(size: 13))
                            
                            Button(action: {
                                openTermsOfService()
                            }) {
                                Text(t("Terms of Service"))
                                    .font(.system(size: 13))
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            if localizer.appLanguage == "ja" {
                                Text(t("to agree"))
                                    .font(.system(size: 13))
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 40)
            
            Button(action: {
                if !validateInputs() { return }
                Task {
                    await handleAuth()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView().controlSize(.small)
                            .padding(.trailing, 5)
                    }
                    Text(isRegistering ? t("Sign Up") : t("Log In"))
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
            .disabled(isLoading)
            .keyboardShortcut(.defaultAction)
            
            Button(action: {
                withAnimation {
                    isRegistering.toggle()
                }
                errorMessage = nil
                confirmPassword = ""
            }) {
                Text(isRegistering ? t("Already have an account? Log In") : t("Don't have an account? Sign Up"))
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            
            }
            
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
    
    private func handleAuth() async {
        isLoading = true
        errorMessage = nil
        do {
            if isRegistering {
                try await authManager.register(email: email, password: password)
                // Registration succeeded, show OTP Verification
                withAnimation {
                    showOTPVerification = true
                }
                startResendTimer()
            } else {
                try await authManager.login(email: email, password: password)
                presentationMode.wrappedValue.dismiss()
            }
        } catch {
            let errorMsg = error.localizedDescription
            if errorMsg.lowercased().contains("potwierdzon") || errorMsg.lowercased().contains("confirm") {
                withAnimation {
                    showOTPVerification = true
                }
                startResendTimer()
            } else {
                errorMessage = tError(errorMsg)
            }
        }
        isLoading = false
    }
    
    private func handleOTPVerification() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authManager.verifyOTP(email: email, token: otpToken)
            presentationMode.wrappedValue.dismiss()
        } catch {
            let errorMsg = error.localizedDescription
            if errorMsg.lowercased().contains("token has expired or is invalid") || errorMsg.lowercased().contains("invalid") {
                errorMessage = t("Token has expired or is invalid.")
            } else {
                errorMessage = tError(errorMsg)
            }
        }
        isLoading = false
    }
    
    private func validateInputs() -> Bool {
        errorMessage = nil
        
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            errorMessage = t("Please enter your email address.")
            return false
        }
        
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        if !emailPred.evaluate(with: trimmedEmail) {
            errorMessage = t("Please enter a valid email address.")
            return false
        }
        
        if password.isEmpty {
            errorMessage = t("Please enter your password.")
            return false
        }
        
        if isRegistering {
            if password.count < 6 {
                errorMessage = t("Password must be at least 6 characters long.")
                return false
            }
            
            if password.rangeOfCharacter(from: .uppercaseLetters) == nil {
                errorMessage = t("Password must contain at least one uppercase letter.")
                return false
            }
            
            if password.rangeOfCharacter(from: .lowercaseLetters) == nil {
                errorMessage = t("Password must contain at least one lowercase letter.")
                return false
            }
            
            if password.rangeOfCharacter(from: .decimalDigits) == nil {
                errorMessage = t("Password must contain at least one number.")
                return false
            }
            
            if confirmPassword.isEmpty {
                errorMessage = t("Please repeat your password.")
                return false
            }
            
            if password != confirmPassword {
                errorMessage = t("Passwords do not match.")
                return false
            }
            
            if !acceptedPrivacyPolicy {
                errorMessage = t("Please accept the Privacy Policy and Terms of Service to create an account.")
                return false
            }
        }
        
        return true
    }
    
    private func openPrivacyPolicy() {
        let lang = localizer.appLanguage.uppercased()
        let suffix = "(\(lang)).pdf"
        
        let bundleUrls = Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: nil) ?? []
        let politicsUrls = Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: "Politics") ?? []
        let allUrls = bundleUrls + politicsUrls
        
        if let matched = allUrls.first(where: { $0.lastPathComponent.contains(suffix) }) {
            NSWorkspace.shared.open(matched)
        } else if let fallback = allUrls.first(where: { $0.lastPathComponent.contains("(EN).pdf") }) {
            NSWorkspace.shared.open(fallback)
        }
    }
    
    private func openTermsOfService() {
        let lang = localizer.appLanguage.uppercased()
        let suffix = "(\(lang)).pdf"
        
        let bundleUrls = Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: nil) ?? []
        let termsUrls = Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: "Terms") ?? []
        let allUrls = bundleUrls + termsUrls
        
        if lang == "EN" {
            if let matched = allUrls.first(where: { $0.lastPathComponent.contains("(Updated).pdf") }) {
                NSWorkspace.shared.open(matched)
                return
            }
        }
        
        if let matched = allUrls.first(where: { $0.lastPathComponent.contains(suffix) }) {
            NSWorkspace.shared.open(matched)
        } else if let fallback = allUrls.first(where: { $0.lastPathComponent.contains("(Updated).pdf") }) {
            NSWorkspace.shared.open(fallback)
        }
    }
}
