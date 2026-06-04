import SwiftUI

struct UserProfileOTPView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var authManager: AuthManager
    let colorScheme: ColorScheme
    @FocusState private var focusedField: Int?
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
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
            
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    TextField("", text: $viewModel.otpDigits[index])
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
                        .onChange(of: viewModel.otpDigits[index]) {
                            let newValue = viewModel.otpDigits[index]
                            let oldVal = viewModel.oldOtpDigits[index]
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.isEmpty {
                                if newValue == "" {
                                    viewModel.otpDigits[index] = "\u{200B}"
                                    viewModel.oldOtpDigits[index] = "\u{200B}"
                                    if index > 0 {
                                        focusedField = index - 1
                                    }
                                } else if newValue == "\u{200B}" {
                                    viewModel.oldOtpDigits[index] = "\u{200B}"
                                } else {
                                    viewModel.otpDigits[index] = oldVal
                                }
                                return
                            }
                            if filtered.count > 1 {
                                let chars = Array(filtered.prefix(6))
                                for i in 0..<chars.count {
                                    if index + i < 6 {
                                        viewModel.otpDigits[index + i] = String(chars[i])
                                        viewModel.oldOtpDigits[index + i] = String(chars[i])
                                    }
                                }
                                focusedField = min(index + chars.count, 5)
                            } else {
                                viewModel.otpDigits[index] = filtered
                                viewModel.oldOtpDigits[index] = filtered
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
            .onChange(of: focusedField) {
                if let newIndex = focusedField {
                    let firstEmpty = viewModel.otpDigits.firstIndex(where: { $0 == "\u{200B}" || $0.isEmpty }) ?? 5
                    if newIndex > firstEmpty {
                        focusedField = firstEmpty
                    }
                }
            }
            .onAppear {
                focusedField = 0
                viewModel.updateCooldown()
                viewModel.startResendTimer()
            }
            
            Button(action: {
                Task {
                    viewModel.isLoadingOTP = true
                    viewModel.changePasswordError = nil
                    do {
                        if let email = authManager.currentUserEmail {
                            try await authManager.verifyPasswordChangeOTP(email: email, token: viewModel.otpToken)
                            UserDefaults.standard.set(0.0, forKey: "lastPasswordOTPSentTime")
                            withAnimation {
                                viewModel.isVerifyingOTPForPassword = false
                                viewModel.isChangingPassword = true
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
            .disabled(viewModel.isLoadingOTP || viewModel.otpToken.isEmpty)
            .keyboardShortcut(.defaultAction)
            
            Button(action: {
                Task {
                    viewModel.isLoadingOTP = true
                    let lastSent = UserDefaults.standard.double(forKey: "lastPasswordOTPSentTime")
                    let elapsed = Date().timeIntervalSince1970 - lastSent
                    
                    if elapsed >= 60 {
                        do {
                            if let email = authManager.currentUserEmail {
                                try await authManager.requestPasswordChangeOTP(email: email)
                                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPasswordOTPSentTime")
                                viewModel.startResendTimer()
                                viewModel.changePasswordError = nil
                            }
                        } catch {
                            viewModel.changePasswordError = error.localizedDescription
                        }
                    } else {
                        if viewModel.resendCooldown == 0 {
                            viewModel.resendCooldown = Int(60 - elapsed)
                            viewModel.startResendTimer()
                        }
                    }
                    viewModel.isLoadingOTP = false
                }
            }) {
                Text(viewModel.resendCooldown > 0 ? t("Resend Email") + " (\(viewModel.resendCooldown)s)" : t("Resend Email"))
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.resendCooldown > 0 ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .disabled(viewModel.resendCooldown > 0 || viewModel.isLoadingOTP)
            
            Button(action: {
                withAnimation {
                    viewModel.isVerifyingOTPForPassword = false
                    viewModel.showSendEmailConfirmation = false
                    viewModel.changePasswordError = nil
                    viewModel.resetOTPState()
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
    }
}
