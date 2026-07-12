import SwiftUI

struct UserProfileSendEmailConfirmationView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var authManager: AuthManager
    let colorScheme: ColorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 14) {
            Text(t("Confirm Email"))
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 10)
            
            Text(t("To continue, you need to confirm your email address. A 6-digit code will be sent to your email. (Check your spam folder)"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
            
            if let error = viewModel.changePasswordError {
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
                    viewModel.isLoadingOTP = true
                    viewModel.changePasswordError = nil
                    do {
                        if let email = authManager.currentUserEmail {
                            try await authManager.requestPasswordChangeOTP(email: email)
                            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPasswordOTPSentTime")
                            viewModel.startResendTimer()
                            withAnimation {
                                viewModel.showSendEmailConfirmation = false
                                viewModel.isVerifyingOTPForPassword = true
                            }
                        }
                    } catch {
                        viewModel.changePasswordError = error.localizedDescription
                    }
                    viewModel.isLoadingOTP = false
                }
            }) {
                HStack {
                    if viewModel.isLoadingOTP {
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
            .disabled(viewModel.isLoadingOTP)
            .keyboardShortcut(.defaultAction)
            
            Button(action: {
                withAnimation {
                    viewModel.showSendEmailConfirmation = false
                    viewModel.changePasswordError = nil
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
    }
}
