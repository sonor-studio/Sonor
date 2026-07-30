import SwiftUI

struct FeedbackView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var feedbackType = "Idea"
    @State private var customCategory = ""
    @State private var emailAddress = ""
    @State private var feedbackText = ""
    @State private var isSubmitting = false
    @State private var showSuccessMessage = false
    @State private var errorMessage = ""
    @State private var isClearingForm = false
    let feedbackTypes = ["Idea", "Bug Report", "Question", "Other"]
    
    private var isEmailValid: Bool {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: trimmed)
    }
    
    private var isCategoryValid: Bool {
        if feedbackType == "Other" {
            return !customCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 40) {
                // Left Side: Feedback Form
            VStack(alignment: .center, spacing: 20) {
                Text(t("Send Feedback"))
                    .font(.title)
                    .fontWeight(.bold)
                    
                Text(t("We value your input! Share your thoughts, report issues, or suggest new features to help us improve Sonor."))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                
                Picker("", selection: $feedbackType) {
                    ForEach(feedbackTypes, id: \.self) { type in
                        Text(t(type)).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity)
                
                if feedbackType == "Other" {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(t("Enter custom category..."), text: $customCategory)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: .infinity)
                        
                        if !isCategoryValid {
                            Text(t("This field is required"))
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.leading, 4)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    TextField(t("Optional: Email address"), text: $emailAddress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                    
                    if !isEmailValid {
                        Text(t("Invalid email address"))
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.leading, 4)
                    }
                }
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $feedbackText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white)
                        .cornerRadius(12)
                    
                    if feedbackText.isEmpty {
                        Text(t("Write your feedback here..."))
                            .font(.body)
                            .foregroundColor(Color.secondary.opacity(0.5))
                            .padding(.leading, 16)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .frame(minHeight: 250)
                
                Button(action: {
                    submitToSupabase()
                }) {
                    let isDisabled = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting || !isEmailValid || !isCategoryValid
                    
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                    } else {
                        Text(showSuccessMessage ? t("Thank You!") : t("Submit Feedback"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isDisabled ? Color.secondary : (colorScheme == .dark ? .black : .white))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(isDisabled ? Color.primary.opacity(0.1) : Color.primary)
                            .cornerRadius(10)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting || !isEmailValid || !isCategoryValid)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Right Side: GitHub Info
            VStack(alignment: .center, spacing: 20) {
                Text(t("Community & Support"))
                    .font(.title)
                    .fontWeight(.bold)
                
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.primary)
                    .padding(.vertical, 20)
                
                Text(t("Sonor is an open platform. We track bugs, feature requests, and community discussions on GitHub. You can also view existing issues to see what we are currently working on."))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                
                Button(action: {
                    if let url = URL(string: "https://github.com/sonor-studio/Sonor/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 18))
                        Text(t("Open GitHub Issues"))
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
        
        Text(t("We carefully review all reports, ideas, and questions to improve Sonor. While we may not be able to reply to every message personally, your feedback is highly appreciated and helps shape our future updates."))
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onChange(of: feedbackText, perform: { _ in resetMessages() })
        .onChange(of: customCategory, perform: { _ in resetMessages() })
        .onChange(of: feedbackType, perform: { _ in resetMessages() })
        .onChange(of: emailAddress, perform: { _ in resetMessages() })
    }
    
    private func resetMessages() {
        if isClearingForm { return }
        if showSuccessMessage { showSuccessMessage = false }
        if !errorMessage.isEmpty { errorMessage = "" }
    }
    
    private func submitToSupabase() {
        guard let urlStr = EnvReader.shared.getValue(for: "SUPABASE_URL"),
              let anonKey = EnvReader.shared.getValue(for: "SUPABASE_ANON_KEY"),
              let url = URL(string: "\(urlStr)/rest/v1/feedback") else {
            errorMessage = t("An error occurred. Please try again.")
            return
        }
        
        isSubmitting = true
        errorMessage = ""
        showSuccessMessage = false
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        let finalType = feedbackType == "Other" ? (customCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Other" : customCategory) : feedbackType
        
        let payload: [String: Any] = [
            "type": finalType,
            "description": feedbackText,
            "email": emailAddress
        ]
        
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            isSubmitting = false
            return
        }
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSubmitting = false
                if let error = error {
                    print("Error: \(error)")
                    errorMessage = t("An error occurred. Please try again.")
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Success
                    isClearingForm = true
                    feedbackText = ""
                    customCategory = ""
                    emailAddress = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isClearingForm = false
                        showSuccessMessage = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                if showSuccessMessage {
                                    showSuccessMessage = false
                                }
                            }
                        }
                    }
                } else {
                    errorMessage = t("An error occurred. Please try again.")
                }
            }
        }.resume()
    }

    private func openGitHubIssue() {
        let finalType = feedbackType == "Other" ? (customCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Other" : customCategory) : feedbackType
        let title = "[\(t(finalType))] Feedback"
        let body = feedbackText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://github.com/sonor-studio/Sonor/issues/new?title=\(title)&body=\(body)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
