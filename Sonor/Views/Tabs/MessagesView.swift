import SwiftUI

struct MessagesView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var messageManager = AppMessageManager.shared
    @State private var selectedMessage: AppMessage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            headerView
            
            if messageManager.isLoading && messageManager.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messageManager.messages.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 20) {
                    ForEach(messageManager.messages) { message in
                        Button(action: {
                            selectedMessage = message
                        }) {
                            AppMessageCardView(message: message)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            messageManager.fetchMessages()
        }
        .sheet(item: $selectedMessage) { message in
            AppMessageView(message: message)
                .preferredColorScheme(colorScheme)
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Image(systemName: "tray.fill")
                .font(.system(size: 24))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text(t("Messages"))
                .font(.system(size: 28, weight: .bold))
            Spacer()
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(t("No messages yet"))
                .font(.system(size: 20, weight: .semibold))
            Text(t("You will see announcements and updates here."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

struct AppMessageCardView: View {
    @Environment(\.colorScheme) var colorScheme
    let message: AppMessage
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(message.header)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if let dateStr = message.created_at, let date = parseDate(dateStr) {
                    Text(formatDate(date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(message.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            let processedDescription = message.description
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\r\n", with: "\n")
            
            Text(processedDescription)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(isHovered ? 0.05 : 0.03) : Color.black.opacity(isHovered ? 0.04 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(isHovered ? 0.2 : 0.1) : Color.black.opacity(isHovered ? 0.15 : 0.08), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func parseDate(_ dateStr: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: dateStr) { return d }
        
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateStr)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
