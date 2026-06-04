import SwiftUI

struct RamHistoryView: View {
    @ObservedObject var memoryManager: MessageMemoryManager
    let colorScheme: ColorScheme
    @State private var hoveredCardId: UUID? = nil
    @State private var hoveredCopyId: UUID? = nil
    @State private var hoveredTrashId: UUID? = nil
    @State private var isHoveringClearHistory = false
    @State private var isShowingRamExplanation = false
    @State private var currentPage = 0
    let itemsPerPage = 5
    var reversedMessages: [MemoryMessage] {
        memoryManager.messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.reversed()
    }
    var totalPages: Int {
        let count = reversedMessages.count
        guard count > 0 else { return 1 }
        return Int(ceil(Double(count) / Double(itemsPerPage)))
    }
    var paginatedMessages: [MemoryMessage] {
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, reversedMessages.count)
        guard startIndex < reversedMessages.count else { return [] }
        return Array(reversedMessages[startIndex..<endIndex])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(t("Text History"))
                        .font(.system(size: 20, weight: .bold))
                    let isRAM = memoryManager.historyStorageType == "RAM"
                    HStack(spacing: 5) {
                        Image(systemName: isRAM ? "memorychip" : "doc.text.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(t(isRAM ? "Temporary RAM" : "Local File"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundColor(.primary)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.leading, 4)
                    Button(action: {
                        isShowingRamExplanation = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(t("Learn more about RAM history"))
                }
                Spacer()
                if !reversedMessages.isEmpty {
                    Button(action: {
                        withAnimation {
                            memoryManager.clearHistory()
                        }
                    }) {
                        Text(t("Clear history"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(isHoveringClearHistory ? .white : .red)
                            .background(isHoveringClearHistory ? Color.red : Color.clear)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red, lineWidth: 1)
                            )
                            .animation(.easeInOut(duration: 0.15), value: isHoveringClearHistory)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringClearHistory = hovering
                    }
                }
            }
            if reversedMessages.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: memoryManager.historyStorageType == "File" ? "doc.text.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(t(memoryManager.historyStorageType == "File" ? "No saved texts" : "No saved texts in RAM"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(t(memoryManager.historyStorageType == "File" ? "Every processed text will appear here and be stored securely in your persistent local history file." : "Every processed text will appear here temporarily. Closing Sonor or clearing the history will permanently delete this data."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [5, 5], dashPhase: 0))
                )
            } else {
                VStack(spacing: 12) {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(paginatedMessages) { msg in
                                MessageCardView(
                                    msg: msg,
                                    colorScheme: colorScheme,
                                    isCardHovered: hoveredCardId == msg.id,
                                    isCopyHovered: hoveredCopyId == msg.id,
                                    isTrashHovered: hoveredTrashId == msg.id,
                                    onCopyHover: { hovering in
                                        hoveredCopyId = hovering ? msg.id : nil
                                    },
                                    onDeleteHover: { hovering in
                                        hoveredTrashId = hovering ? msg.id : nil
                                    },
                                    onCardHover: { hovering in
                                        hoveredCardId = hovering ? msg.id : nil
                                    },
                                    onDelete: {
                                        memoryManager.deleteMessage(id: msg.id)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 400) 
                    if totalPages > 1 {
                        HStack(spacing: 20) {
                            Spacer()
                            Button(action: {
                                if currentPage > 0 {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPage -= 1
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(currentPage > 0 ? Color.primary.opacity(0.08) : Color.clear)
                                .foregroundColor(currentPage > 0 ? .primary : .secondary.opacity(0.3))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentPage == 0)
                            Text(String(format: t("Page %d of %d"), currentPage + 1, totalPages))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 80)
                                .multilineTextAlignment(.center)
                            Button(action: {
                                if currentPage < totalPages - 1 {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPage += 1
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(currentPage < totalPages - 1 ? Color.primary.opacity(0.08) : Color.clear)
                                .foregroundColor(currentPage < totalPages - 1 ? .primary : .secondary.opacity(0.3))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentPage == totalPages - 1)
                            Spacer()
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
        .onChange(of: reversedMessages.count) {
            let maxPage = max(0, Int(ceil(Double(reversedMessages.count) / Double(itemsPerPage))) - 1)
            if currentPage > maxPage {
                currentPage = maxPage
            }
        }
        .sheet(isPresented: $isShowingRamExplanation) {
            RamHistoryExplanationView()
                .preferredColorScheme(colorScheme)
        }
    }
}

struct MessageCardView: View {
    let msg: MemoryMessage
    let colorScheme: ColorScheme
    let isCardHovered: Bool
    let isCopyHovered: Bool
    let isTrashHovered: Bool
    let onCopyHover: (Bool) -> Void
    let onDeleteHover: (Bool) -> Void
    let onCardHover: (Bool) -> Void
    let onDelete: () -> Void
    @State private var isCopied = false
    @State private var isExpanded = false
    private var copyBgColor: Color {
        if isCopyHovered {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
        } else {
            return Color.clear
        }
    }
    private var copyFgColor: Color {
        if isCopyHovered {
            return colorScheme == .dark ? Color.white : Color.black
        } else {
            return Color.secondary
        }
    }
    private var deleteBgColor: Color {
        if isTrashHovered {
            return Color.red.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    private var deleteFgColor: Color {
        if isTrashHovered {
            return Color.red
        } else {
            return Color.secondary
        }
    }
    private var cardBgColor: Color {
        if colorScheme == .dark {
            return isCardHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.025)
        } else {
            return isCardHovered ? Color.black.opacity(0.03) : Color.black.opacity(0.015)
        }
    }
    private var cardStrokeColor: Color {
        if isCardHovered {
            return colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(msg.date, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(msg.text, forType: .string)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isCopied = false
                            }
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(copyBgColor)
                                .frame(width: 26, height: 26)
                            if isCopied {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.green)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(copyFgColor)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(t("Copy text"))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onCopyHover(hovering)
                        }
                    }
                    Button(action: {
                        withAnimation {
                            onDelete()
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(deleteBgColor)
                                .frame(width: 26, height: 26)
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(deleteFgColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(t("Delete entry"))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onDeleteHover(hovering)
                        }
                    }
                }
            }
            Text(msg.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineSpacing(3)
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                onCardHover(hovering)
            }
        }
    }
}
