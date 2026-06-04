import SwiftUI

struct UserProfileMainView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var authManager: AuthManager
    @ObservedObject var networkMonitor: NetworkMonitor
    let colorScheme: ColorScheme
    let dismiss: DismissAction
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                .padding(.top, 10)
                .padding(.bottom, 16)
            
            Text(t(authManager.accountTier.uppercased()))
                .font(.system(size: 10, weight: .black))
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(colorScheme == .dark ? Color.white : Color.black)
                .cornerRadius(4)
                .padding(.bottom, 16)
            
            VStack(spacing: 6) {
                Text(authManager.currentUserEmail ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(t("Member since:")) \(viewModel.formattedCreationDate(authManager: authManager, localizer: localizer))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 30)
            
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Toggle(t("Email Updates"), isOn: Binding(
                        get: { viewModel.localMarketingOptIn },
                        set: { newValue in
                            if !newValue {
                                viewModel.showUnsubscribeConfirmation = true
                            } else {
                                viewModel.localMarketingOptIn = true
                                viewModel.updateMarketingConsent(authManager: authManager, networkMonitor: networkMonitor, newValue: true)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .focusable(false)
                    .accentColor(colorScheme == .dark ? .white : .black)
                    .tint(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    if viewModel.isUpdatingConsent {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(12)
                .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                .cornerRadius(8)
                .padding(.horizontal, 24)
            }
            .alert(t("Are you sure?"), isPresented: $viewModel.showUnsubscribeConfirmation) {
                Button(t("Unsubscribe"), role: .destructive) {
                    viewModel.localMarketingOptIn = false
                    viewModel.updateMarketingConsent(authManager: authManager, networkMonitor: networkMonitor, newValue: false)
                }
                Button(t("Cancel"), role: .cancel) {}
            } message: {
                Text(t("Are you sure you want to unsubscribe from email updates about new products and upcoming changes?"))
            }
            .padding(.bottom, 10)
            
            Spacer()
            
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
            
            if authManager.currentUserProvider != "google" {
                Button(action: {
                    if !networkMonitor.isConnected {
                        viewModel.deleteError = t("Please connect to the internet to perform this action.")
                        return
                    }
                    viewModel.deleteError = nil
                    let lastSent = UserDefaults.standard.double(forKey: "lastPasswordOTPSentTime")
                    let elapsed = Date().timeIntervalSince1970 - lastSent
                    
                    if elapsed < 60 {
                        viewModel.resendCooldown = Int(60 - elapsed)
                    } else {
                        viewModel.resendCooldown = 0
                    }
                    
                    if elapsed >= 60 {
                        withAnimation {
                            viewModel.showSendEmailConfirmation = true
                        }
                    } else {
                        withAnimation {
                            viewModel.isVerifyingOTPForPassword = true
                        }
                        viewModel.startResendTimer()
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
            
            Button(action: {
                if !networkMonitor.isConnected {
                    viewModel.deleteError = t("Please connect to the internet to perform this action.")
                    return
                }
                viewModel.deleteError = nil
                viewModel.showDeleteConfirmation = true
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
            
            if let deleteError = viewModel.deleteError {
                Text(deleteError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }
            
            if viewModel.isDeleting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 10)
            }
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
}
