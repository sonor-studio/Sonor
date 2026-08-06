import SwiftUI
import Hub

struct ModelCard: View {
    let title: String
    let description: String
    let state: DownloadState
    var progressText: String? = nil
    var isActive: Bool? = nil
    var onSetActive: (() -> Void)? = nil
    let onDownload: () -> Void
    var onPause: (() -> Void)? = nil
    let onCancel: () -> Void
    var onUninstall: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t(title))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t(description))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                switch state {
                case .notDownloaded:
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
                case .downloading(let progress):
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 12) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(colorScheme == .dark ? .white : .black)
                                .frame(width: 100)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
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
                        if let pt = progressText {
                            Text(pt)
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                case .paused(let progress):
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 12) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(.secondary)
                                .frame(width: 100)
                                .opacity(0.6)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
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
                        if let pt = progressText {
                            Text(pt)
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                case .downloaded:
                    HStack(spacing: 12) {
                        if let isActive = isActive, let onSetActive = onSetActive {
                            if isActive {
                                Text(t("Active"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(colorScheme == .dark ? Color.white : Color.black)
                                    .cornerRadius(6)
                            } else {
                                Button(action: onSetActive) {
                                    Text(t("Set Active"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let onUninstall = onUninstall {
                            if title != "Apple Speech (System)" {
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
