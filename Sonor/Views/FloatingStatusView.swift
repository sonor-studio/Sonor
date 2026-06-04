import SwiftUI

struct FloatingStatusView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(controller.isRecording ? Color.red : Color.gray)
                .frame(width: 12, height: 12)
                .opacity(controller.isRecording ? 1.0 : 0.5)
                .scaleEffect(controller.isRecording ? (1.0 + CGFloat(controller.audioLevel * 0.5)) : 1.0)
                .animation(.easeInOut(duration: 0.1), value: controller.audioLevel)
                .animation(.easeInOut(duration: 0.3), value: controller.isRecording)
            Text(t(controller.statusText))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Material.ultraThin)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
