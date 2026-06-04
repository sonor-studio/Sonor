import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var localizer = LocalizationManager.shared
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                HStack(spacing: 6) {
                    Text("Sonor")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    Text(t("Beta"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(4)
                }
                Spacer()
                Text(t(controller.statusText))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(controller.isRecording ? .red : .primary)
            }
            .padding(.horizontal, 4)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
                    .frame(height: 80)
                HStack(spacing: 3) {
                    ForEach(0..<controller.audioLevels.count, id: \.self) { index in
                        let level = controller.audioLevels[index]
                        let barHeight = CGFloat(4 + (level * 150))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: controller.isRecording ? [.red, .orange] : [.blue, .cyan],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 3, height: min(barHeight, 60))
                            .opacity(Double(index) / Double(controller.audioLevels.count)) 
                            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: level)
                    }
                }
            }
            .onTapGesture {
                controller.toggleRecording()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cmd + Shift + `")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(t("Record / Stop"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
                Button(action: { WindowManager.shared.openSettings() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
                }
                .buttonStyle(.plain)
                Button(action: { controller.quitApp() }) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 280, height: 200)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow).ignoresSafeArea())
    }
}


struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
