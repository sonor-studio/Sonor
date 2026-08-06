import SwiftUI
import Hub

struct RichModelCard: View {
    let title: String
    let description: String
    let weight: String
    let languages: String
    let accuracy: Double
    let speed: Double
    let company: String
    let parameters: String?
    let supportedLanguagesList: [String]
    let state: DownloadState
    var progressText: String? = nil
    var isActive: Bool? = nil
    var isExpandable: Bool = false
    var onSetActive: (() -> Void)? = nil
    let onDownload: () -> Void
    var onPause: (() -> Void)? = nil
    let onCancel: () -> Void
    var onUninstall: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded: Bool = false
    @State private var showLanguageList: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topRow
            detailSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: isActive) { _, newValue in
            if isExpandable, let act = newValue, act == true {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded = true
                }
            }
        }
        .onAppear {
            if isExpandable, let act = isActive, act == true {
                isExpanded = true
            }
        }
        .sheet(isPresented: $showLanguageList) {
            LanguageListView(languages: supportedLanguagesList)
        }
    }

    private var cardFillColor: Color {
        if isExpanded || !isExpandable {
            return colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01)
        }
    }

    // Top Row: Title, Weight & Actions
    private var topRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(t(description))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()

            actionButtons
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isExpandable {
                if let act = isActive, act == true, isExpanded == true {
                    return // Do not collapse if active
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
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
                                .foregroundColor(colorScheme == .dark ? .white : .black)
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

    @ViewBuilder
    private var detailSection: some View {
        if !isExpandable || isExpanded {
            VStack(alignment: .leading, spacing: 16) {
                metadataTags
                progressBars
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // Metadata Tags
    private var metadataTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                weightTag
                languageTagButton
                companyTag
                if let params = parameters {
                    parametersTag(params)
                }
            }
        }
    }

    private var weightTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "shippingbox")
                .foregroundColor(.secondary)
            Text(t("Weight") + ": " + weight)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        .cornerRadius(4)
    }

    private var languageTagButton: some View {
        Button(action: {
            showLanguageList = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                Text(t("Languages") + ": " + t(languages))
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private var companyTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "building.2")
                .foregroundColor(.secondary)
            Text(t(company))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        .cornerRadius(4)
    }

    private func parametersTag(_ params: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .foregroundColor(.secondary)
            Text(t(params))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        .cornerRadius(4)
    }

    // Progress Bars
    private var progressBars: some View {
        VStack(spacing: 8) {
            HStack {
                Text(t("Accuracy"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 80, alignment: .leading)
                ProgressView(value: accuracy)
                    .progressViewStyle(.linear)
                    .tint(colorScheme == .dark ? .white : .black)
            }
            HStack {
                Text(t("Speed"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 80, alignment: .leading)
                ProgressView(value: speed)
                    .progressViewStyle(.linear)
                    .tint(colorScheme == .dark ? .white : .black)
            }
        }
    }
}
