import SwiftUI

struct TimeSavedMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let hoursSaved: Int
    
    var body: some View {
        VStack(spacing: 24) {
            // Ikona nagrody w monochromatycznym motywie
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "star.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .padding(.top, 10)
            
            VStack(spacing: 12) {
                Text(t("Congratulations!"))
                    .font(.system(size: 24, weight: .black))
                    .multilineTextAlignment(.center)
                
                Text(String(format: t("You have already saved %d hours thanks to Sonor!"), hoursSaved))
                    .font(.system(size: 18, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text(t("If you appreciate our work and the time you've saved, consider supporting the creator by buying them a virtual coffee."))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .lineSpacing(4)
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    if let url = URL(string: "https://buymeacoffee.com/sonorstudio") {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                        Text(t("Buy me a coffee"))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                
                Button(action: {
                    dismiss()
                }) {
                    Text(t("Maybe later"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.clear)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
        }
        .padding(30)
        .frame(width: 400)
    }
}
