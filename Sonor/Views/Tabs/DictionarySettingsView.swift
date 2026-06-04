import SwiftUI

struct DictionarySettingsView: View {
    @Binding var showLoginSheet: Bool
    @ObservedObject var localizer = LocalizationManager.shared
    @State private var entries: [String: String] = [:]
    @State private var newWrong: String = ""
    @State private var newCorrect: String = ""
    @Environment(\.colorScheme) var colorScheme
    @State private var isHoveringAdd = false
    @State private var hoveredKey: String? = nil
    @State private var isShowingInfo = false
    private var sortedKeys: [String] {
        entries.keys.sorted()
    }
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                Text(t("Dictionary"))
                    .font(.system(size: 28, weight: .bold))
                Button(action: {
                    isShowingInfo = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(t("Learn more about Dictionary"))
            }
        }
        .padding(.bottom, 8)
    }
    private var wrongInputView: some View {
        TextField(t("e.g. Superbase"), text: $newWrong)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
            )
    }
    private var correctInputView: some View {
        TextField(t("e.g. Supabase"), text: $newCorrect)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
            )
    }
    private var isAddButtonActive: Bool {
        !newWrong.isEmpty && !newCorrect.isEmpty
    }
    private var addButtonColor: Color {
        if isAddButtonActive {
            return colorScheme == .dark ? .white : .black
        } else {
            return Color.primary.opacity(0.1)
        }
    }
    private var addButtonView: some View {
        Button(action: addEntry) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isAddButtonActive ? (colorScheme == .dark ? .black : .white) : Color.primary.opacity(0.35))
                .frame(width: 38, height: 38)
                .background(addButtonColor)
                .cornerRadius(10)
                .scaleEffect(isHoveringAdd && isAddButtonActive ? 1.05 : 1.0)
                .animation(.spring(), value: isHoveringAdd)
        }
        .buttonStyle(.plain)
        .disabled(!isAddButtonActive)
        .onHover { hovering in
            isHoveringAdd = hovering
        }
    }
    private var addFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("ADD NEW CORRECTION"))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Text(t("When it hears"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                        .frame(width: 20)
                    Text(t("Replace with"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                        .frame(width: 38)
                }
                HStack(spacing: 16) {
                    wrongInputView
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 38)
                    correctInputView
                    addButtonView
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    private func rowView(key: String, value: String) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("When it hears"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(key)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Replace with (list)"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { removeEntry(key: key) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredKey == key ? Color.red.opacity(0.1) : Color.clear)
                        .frame(width: 32, height: 32)
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(hoveredKey == key ? .red : .secondary)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if hovering {
                        hoveredKey = key
                    } else if hoveredKey == key {
                        hoveredKey = nil
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.01) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerView
            if !AuthManager.shared.isLoggedIn {
                PremiumLockView(showLoginSheet: $showLoginSheet)
            } else {
                addFormView
                HStack {
                    Text(String(format: t("SAVED CORRECTIONS (%d)"), entries.count))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    Spacer()
                }
                .padding(.top, 8)
                if entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(t("No dictionary entries"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(t("Add the first correction above to automatically fix the most common Sonor errors."))
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
                        ForEach(sortedKeys, id: \.self) { key in
                            if let value = entries[key] {
                                rowView(key: key, value: value)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingInfo) {
            DictionaryExplanationView()
        }
        .onAppear(perform: loadEntries)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("VoiceModesUpdated"))) { _ in
            loadEntries()
        }
    }
    func loadEntries() {
        entries = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
    }
    func addEntry() {
        entries[newWrong] = newCorrect
        UserDefaults.standard.set(entries, forKey: "dictionaryEntries")
        newWrong = ""
        newCorrect = ""
    }
    func removeEntry(key: String) {
        withAnimation {
            entries.removeValue(forKey: key)
            UserDefaults.standard.set(entries, forKey: "dictionaryEntries")
        }
    }
}
