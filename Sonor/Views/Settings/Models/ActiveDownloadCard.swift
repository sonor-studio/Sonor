import SwiftUI
import Hub

struct ActiveDownloadCard: View {
    let title: String
    let descriptionText: String
    let state: DownloadState
    let stats: ModelManager.DownloadStats?
    
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    Text(t(descriptionText))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                
                if isExpanded {
                    // Status Tag
                    HStack(spacing: 4) {
                        if state.isDownloading {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(t("Downloading"))
                        } else if state.isPaused {
                            Image(systemName: "pause.circle.fill")
                            Text(t("Paused"))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(state.isDownloading ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            
            Divider().padding(.vertical, -4)
            
            if isExpanded {
                // Stats Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        let progressPct = (stats?.totalBytes ?? 0) > 0 ? Double(stats?.downloadedBytes ?? 0) / Double(stats?.totalBytes ?? 1) : 0
                        Text(String(format: "%.1f%%", progressPct * 100))
                            .font(.system(size: 24, weight: .bold).monospacedDigit())
                        
                        if let stats = stats, stats.totalBytes > 0 {
                            Text("\(formatBytes(stats.downloadedBytes)) / \(formatBytes(stats.totalBytes))")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        if let stats = stats {
                            let speedStr = formatBytes(Int64(stats.speedBytesPerSecond))
                            Text("\(speedStr)/s")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundColor(state.isDownloading ? .primary : .secondary)
                                
                            let remainingBytes = stats.totalBytes - stats.downloadedBytes
                            if remainingBytes > 0 && stats.speedBytesPerSecond > 0 {
                                let recentSpeeds = stats.speedHistory.suffix(10)
                                let avgSpeed = recentSpeeds.isEmpty ? stats.speedBytesPerSecond : (recentSpeeds.reduce(0, +) / Double(recentSpeeds.count))
                                let effectiveSpeed = avgSpeed > 0 ? avgSpeed : stats.speedBytesPerSecond
                                let secondsRemaining = Double(remainingBytes) / effectiveSpeed
                                Text("\(t("Time left:")) \(formatTime(seconds: secondsRemaining))")
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundColor(.secondary)
                            } else {
                                Text(t("Current Speed"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("0 KB/s")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundColor(.secondary)
                            Text(t("Current Speed"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Chart Area
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
                        .frame(height: 60)
                    
                    if let stats = stats, !stats.speedHistory.isEmpty {
                        DownloadSpeedChart(history: stats.speedHistory)
                            .frame(height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            
            // Controls & Progress
            HStack(spacing: 12) {
                // Play/Pause
                Button(action: {
                    if state.isDownloading {
                        onPause()
                    } else if case .paused = state {
                        onResume()
                    }
                }) {
                    Image(systemName: state.isDownloading ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(width: 32, height: 32)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                let progressPct = (stats?.totalBytes ?? 0) > 0 ? Double(stats?.downloadedBytes ?? 0) / Double(stats?.totalBytes ?? 1) : 0
                
                if !isExpanded {
                    Text(String(format: "%.0f%%", progressPct * 100))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(state.isDownloading ? (colorScheme == .dark ? Color.white : Color.black) : Color.secondary)
                            .frame(width: max(0, geo.size.width * CGFloat(progressPct)), height: 8)
                    }
                }
                .frame(height: 8)
                
                // Cancel Button
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatTime(seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds > 31536000 || seconds < -31536000 { return "--:--" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
