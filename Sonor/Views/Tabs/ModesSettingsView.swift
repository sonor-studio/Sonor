import SwiftUI

struct ModesSettingsView: View {
    @Binding var modes: [VoiceMode]
    @Binding var selectedModeID: String
    @Binding var isShowingSidePanel: Bool
    @Environment(\.colorScheme) var colorScheme
    var isPremium: Bool
    @Binding var showLoginSheet: Bool
    @ObservedObject private var localizer = LocalizationManager.shared
    @State private var isShowingInfo = false
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    let columns = [
        GridItem(.adaptive(minimum: 160))
    ]
    @State private var isHoveringPlus = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.primary)
                    Text(t("Assistants"))
                        .font(.system(size: 28, weight: .bold))
                    Button(action: {
                        isShowingInfo = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(t("Learn more about Assistants"))
                }
                Spacer()
                if isPremium {
                    Button(action: {
                        addNewMode()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text(t("Add Assistant"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .cornerRadius(20)
                        .scaleEffect(isHoveringPlus ? 1.05 : 1.0)
                        .animation(.spring(), value: isHoveringPlus)
                        .onHover { hovering in
                            isHoveringPlus = hovering
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView {
                VStack(spacing: 15) {
                    if let rawOutput = modes.first(where: { $0.name == "Raw Output" }) ?? modes.first(where: { $0.name == "Zwykły output" }) {
                        ModeCard(
                            mode: rawOutput,
                            isSelected: selectedModeID == rawOutput.id.uuidString,
                            isPremium: true,
                            isRawOutput: true
                        ) {
                            selectedModeID = rawOutput.id.uuidString
                        } onSettings: {
                            selectedModeID = rawOutput.id.uuidString
                            withAnimation {
                                isShowingSidePanel = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if !isPremium && networkMonitor.isConnected {
                        VStack(spacing: 14) {
                            VStack(spacing: 6) {
                                Text(t("Unlock new assistants after logging in"))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(t("Get access to advanced AI assistants (speech smoothing, professional emails, notes). Everything is 100% free, runs fully offline on your computer, and collects no data."))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            Button(action: {
                                showLoginSheet = true
                            }) {
                                Text(t("Log In"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(colorScheme == .dark ? Color.white : Color.black)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                        .padding(.top, 10)
                    } else {
                        LazyVGrid(columns: columns, spacing: 15) {
                            ForEach(modes.filter { $0.name != "Raw Output" && $0.name != "Zwykły output" }) { mode in
                                ModeCard(
                                    mode: mode,
                                    isSelected: selectedModeID == mode.id.uuidString,
                                    isPremium: isPremium,
                                    isRawOutput: false
                                ) {
                                    selectedModeID = mode.id.uuidString
                                } onSettings: {
                                    selectedModeID = mode.id.uuidString
                                    withAnimation {
                                        isShowingSidePanel = true
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $isShowingInfo) {
            AssistantsExplanationView()
        }
    }
    private func addNewMode() {
        let newMode = VoiceMode(name: "New Assistant", prompt: "Enter your prompt here...", assistantType: "dictation")
        modes.append(newMode)
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: "voiceModes")
            NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
        }
        selectedModeID = newMode.id.uuidString
    }
}
