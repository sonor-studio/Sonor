import SwiftUI

struct DebugConsoleView: View {
    @ObservedObject var logger = DebugLogger.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Konsola Debugowania")
                    .font(.headline)
                Spacer()
                Button("Wyczyść") {
                    logger.clearLogs()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: logger.logs.count) {
                    if logger.logs.count > 0 {
                        withAnimation {
                            proxy.scrollTo(logger.logs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 600, minHeight: 300, idealHeight: 400)
        .onAppear {
            logger.addLog("Konsola otwarta poprawnie!")
        }
    }
}
