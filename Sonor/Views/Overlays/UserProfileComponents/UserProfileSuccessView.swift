import SwiftUI

struct UserProfileSuccessView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
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
                        viewModel.showSuccessMessage = false
                        viewModel.isChangingPassword = false
                        viewModel.resetOTPState()
                    }
                }
            }
        }
    }
}
