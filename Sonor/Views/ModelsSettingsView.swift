import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var manager = ModelManager.shared
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var authManager = AuthManager.shared
    
    @State private var showUninstallConfirmation = false
    @State private var modelToUninstall: ModelType? = nil
    @State private var showLoginSheet = false
    
    enum ModelType {
        case whisper
        case gemma
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                Text(t("Models"))
                    .font(.system(size: 28, weight: .bold))
            }
            
            Text(t("Manage the AI models used by Sonor for transcription and text processing."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
            
            VStack(spacing: 20) {
                ModelCard(
                    title: "Whisper (Speech-to-Text)",
                    description: t("Required for transcribing your voice to text. Approx. 580 MB."),
                    state: manager.whisperState,
                    onDownload: { manager.downloadWhisper() },
                    onCancel: { manager.cancelWhisperDownload() },
                    onUninstall: {
                        self.modelToUninstall = .whisper
                        self.showUninstallConfirmation = true
                    }
                )
                
                ModelCard(
                    title: "Gemma (Text Correction)",
                    description: t("Required for advanced text rewriting and smart corrections. Approx. 3 GB."),
                    state: manager.gemmaState,
                    requiresLogin: !authManager.isLoggedIn,
                    onLogin: { self.showLoginSheet = true },
                    onDownload: { manager.downloadGemma() },
                    onPause: { manager.pauseGemmaDownload() },
                    onCancel: { manager.cancelGemmaDownload() },
                    onUninstall: {
                        self.modelToUninstall = .gemma
                        self.showUninstallConfirmation = true
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .preferredColorScheme(colorScheme)
                .frame(width: 520)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { showLoginSheet = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .padding(15)
                        }
                        Spacer()
                    }
                )
        }
        .alert(isPresented: $showUninstallConfirmation) {
            Alert(
                title: Text(t("Uninstall Model")),
                message: Text(t("Are you sure you want to uninstall this model?")),
                primaryButton: .destructive(Text(t("Uninstall"))) {
                    if let model = modelToUninstall {
                        switch model {
                        case .whisper:
                            manager.uninstallWhisper()
                        case .gemma:
                            manager.uninstallGemma()
                        }
                    }
                },
                secondaryButton: .cancel(Text(t("Cancel")))
            )
        }
    }
}

struct ModelCard: View {
    let title: String
    let description: String
    let state: DownloadState
    var requiresLogin: Bool = false
    var onLogin: (() -> Void)? = nil
    let onDownload: () -> Void
    var onPause: (() -> Void)? = nil
    let onCancel: () -> Void
    let onUninstall: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                switch state {
                case .notDownloaded:
                    if requiresLogin {
                        Button(action: { onLogin?() }) {
                            Text(t("Log In"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(colorScheme == .dark ? Color.white : Color.black)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onDownload) {
                            Text(t("Download"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(colorScheme == .dark ? Color.white : Color.black)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                case .downloading(let progress):
                    HStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(colorScheme == .dark ? .white : .black)
                            .frame(width: 100)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                        
                        if let onPause = onPause {
                            Button(action: onPause) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                case .paused(let progress):
                    HStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.secondary)
                            .frame(width: 100)
                            .opacity(0.6)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                        
                        if requiresLogin {
                            Button(action: onCancel) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { onLogin?() }) {
                                Text(t("Log In"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(colorScheme == .dark ? Color.white : Color.black)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: onDownload) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: onCancel) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                case .downloaded:
                    HStack(spacing: 12) {
                        Button(action: onUninstall) {
                            Text(t("Uninstall"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
