import SwiftUI

struct UserProfileChangePasswordView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var authManager: AuthManager
    @ObservedObject var networkMonitor: NetworkMonitor
    let colorScheme: ColorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 14) {
            Text(t("Change Password"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, 10)
                .padding(.bottom, 6)
            
            if let error = viewModel.changePasswordError {
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
                SecureField(t("Enter old password..."), text: $viewModel.oldPassword)
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
                SecureField(t("Enter new password..."), text: $viewModel.newPassword)
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
                SecureField(t("Repeat new password..."), text: $viewModel.confirmNewPassword)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .cornerRadius(8)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            if viewModel.isSavingPassword {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 20)
            } else {
                Button(action: {
                    viewModel.performPasswordChange(authManager: authManager, networkMonitor: networkMonitor)
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
                
                Button(action: {
                    withAnimation {
                        viewModel.isChangingPassword = false
                        viewModel.oldPassword = ""
                        viewModel.newPassword = ""
                        viewModel.confirmNewPassword = ""
                        viewModel.changePasswordError = nil
                        viewModel.resetOTPState()
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
    }
}
