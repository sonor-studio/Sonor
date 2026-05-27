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
    
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundColor(.primary)
            
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
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
    
    private func handleAuth() async {
        isLoading = true
        errorMessage = nil
        do {
            if isRegistering {
                try await authManager.register(email: email, password: password)
            } else {
                try await authManager.login(email: email, password: password)
            }
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorMessage = tError(error.localizedDescription)
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
        
        if password.count < 6 {
            errorMessage = t("Password must be at least 6 characters long.")
            return false
        }
        
        if isRegistering {
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
