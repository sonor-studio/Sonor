import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var localizer = LocalizationManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isRegistering = false
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.primary)
                .padding(.bottom, 10)
            
            Text(isRegistering ? t("Join Sonor") : t("Welcome Back"))
                .font(.system(size: 24, weight: .bold))
            
            Text(t("Unlock advanced AI assistants, intelligent dictionaries, and custom snippets to turn every recording into polished text. Everything is 100% free and runs fully offline on your computer — your data is completely private, and we do not collect any information."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 10)
            
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
            
            VStack(spacing: 15) {
                TextField(t("Email address"), text: $email)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                
                SecureField(t("Password"), text: $password)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    
                if isRegistering {
                    SecureField(t("Repeat password"), text: $confirmPassword)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
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
                .padding()
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
            .padding(.top, 10)
            
        }
        .padding(.vertical, 40)
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
        }
        
        return true
    }
}
