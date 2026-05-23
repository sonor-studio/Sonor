import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Nagłówek
            HStack {
                Text("Sonor")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(t(controller.statusText))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(controller.isRecording ? .red : .primary)
            }
            .padding(.horizontal, 4)
            
            // Wizualizator ChatGPT-style
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
                    .frame(height: 80)
                
                HStack(spacing: 3) {
                    ForEach(0..<controller.audioLevels.count, id: \.self) { index in
                        let level = controller.audioLevels[index]
                        // Skalowanie wysokości: min 4 (kropka), max 60
                        let barHeight = CGFloat(4 + (level * 150))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: controller.isRecording ? [.red, .orange] : [.blue, .cyan],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 3, height: min(barHeight, 60))
                            .opacity(Double(index) / Double(controller.audioLevels.count)) // Efekt zanikania z lewej
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
                
                Button(action: { controller.openSettings() }) {
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

// Pomocniczy widok dla efektu szklanego tła
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
