import SwiftUI

struct AppMessageView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let message: AppMessage
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            
            VStack(spacing: 12) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(message.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let attributedString = try? AttributedString(markdown: processedMarkdown, options: markdownOptions) {
                        Text(attributedString)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                    } else {
                        // Fallback to basic text
                        Text(message.content_markdown)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Text(t("Close"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 16)
        }
        .frame(width: 440, height: 460)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    private var processedMarkdown: String {
        return message.content_markdown
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "- ", with: "• ")
    }
    
    private var markdownOptions: AttributedString.MarkdownParsingOptions {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return options
    }
}
