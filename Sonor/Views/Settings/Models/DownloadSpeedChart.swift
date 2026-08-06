import SwiftUI
import Hub

struct DownloadSpeedChart: View {
    let history: [Double]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geo in
            let maxSpeed = history.max() ?? 1.0
            let effectiveMax = maxSpeed == 0 ? 1.0 : maxSpeed
            let width = geo.size.width
            let height = geo.size.height
            let safeWidth = (width.isNaN || width.isInfinite) ? 100 : width
            let safeHeight = (height.isNaN || height.isInfinite) ? 10 : height
            
            let barCount = 60
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(max(0, barCount - 1))
            let barWidth = max(1, (safeWidth - totalSpacing) / CGFloat(barCount))
            
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(history.enumerated()), id: \.offset) { index, speed in
                    let rawHeight = CGFloat(speed / effectiveMax) * safeHeight
                    let safeRawHeight = (rawHeight.isNaN || rawHeight.isInfinite) ? 0 : rawHeight
                    let barHeight = max(2, safeRawHeight)
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .frame(width: barWidth, height: barHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
