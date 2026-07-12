import SwiftUI

struct UserProfileView: View {
    @Binding var isShowingProfileSheet: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var localizer = LocalizationManager.shared
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    
    @StateObject private var viewModel = UserProfileViewModel()
    @State private var isCloseHovered = false
    @FocusState private var isDeleteFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
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
                        isShowingProfileSheet = false
                        dismiss()
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            if viewModel.showSuccessMessage {
                UserProfileSuccessView(viewModel: viewModel)
            } else if viewModel.showSendEmailConfirmation {
                UserProfileSendEmailConfirmationView(viewModel: viewModel, authManager: authManager, colorScheme: colorScheme)
            } else if viewModel.isVerifyingOTPForPassword {
                UserProfileOTPView(viewModel: viewModel, authManager: authManager, colorScheme: colorScheme)
            } else if viewModel.isChangingPassword {
                UserProfileChangePasswordView(viewModel: viewModel, authManager: authManager, networkMonitor: networkMonitor, colorScheme: colorScheme)
            } else {
                UserProfileMainView(viewModel: viewModel, authManager: authManager, networkMonitor: networkMonitor, colorScheme: colorScheme, dismiss: dismiss)
            }
        }
        .frame(width: 400, height: 550) 
        .background(colorScheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.05) : Color.white)
        .foregroundColor(.primary)
        .alert(t("Delete Account"), isPresented: $viewModel.showDeleteConfirmation) {
            if authManager.currentUserProvider == "google" {
                Button(t("Delete"), role: .destructive) {
                    viewModel.performAccountDeletion(authManager: authManager, networkMonitor: networkMonitor, dismiss: dismiss)
                }
                Button(t("Cancel"), role: .cancel) {}
            } else {
                SecureField(t("Password"), text: $viewModel.deletePassword)
                    .focused($isDeleteFieldFocused)
                    .onSubmit {
                        viewModel.performAccountDeletion(authManager: authManager, networkMonitor: networkMonitor, dismiss: dismiss)
                    }
                Button(t("Delete"), role: .destructive) {
                    viewModel.performAccountDeletion(authManager: authManager, networkMonitor: networkMonitor, dismiss: dismiss)
                }
                Button(t("Cancel"), role: .cancel) {
                    viewModel.deletePassword = ""
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
            viewModel.localMarketingOptIn = authManager.marketingOptIn
        }
        .onChange(of: authManager.marketingOptIn) {
            viewModel.localMarketingOptIn = authManager.marketingOptIn
        }
        .onDisappear {
            viewModel.cancelTimer()
        }
        .onChange(of: viewModel.showDeleteConfirmation) {
            if viewModel.showDeleteConfirmation {
                triggerDeleteAccountFocus()
            }
        }
        .onChange(of: authManager.isLoggedIn) {
            if !authManager.isLoggedIn {
                isShowingProfileSheet = false
                dismiss()
            }
        }
        .onChange(of: authManager.accountDeletionError) {
            if let error = authManager.accountDeletionError {
                viewModel.deleteError = t(error)
                viewModel.isDeleting = false
            }
        }
    }
    
    private func triggerDeleteAccountFocus() {
        isDeleteFieldFocused = true
        for delay in [0.05, 0.1, 0.15, 0.2, 0.3, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if viewModel.showDeleteConfirmation {
                    isDeleteFieldFocused = true
                }
            }
        }
    }
}
