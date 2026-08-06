import SwiftUI
import Hub

struct CustomDisclosureGroup<Content: View>: View {
    let title: String
    var description: String? = nil
    var modelsCount: Int? = nil
    @State private var isExpanded: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton
            expandedContent
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var headerButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }) {
            headerLabel
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var headerLabel: some View {
        HStack(alignment: .center) {
            titleColumn
            Spacer(minLength: 16)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            if let desc = description {
                Text(t(desc))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 12) {

                VStack(spacing: 12) {
                    content()
                }
                .padding(16)
            }
            .background(colorScheme == .dark ? Color.white.opacity(0.01) : Color.black.opacity(0.005))
        }
    }
}
