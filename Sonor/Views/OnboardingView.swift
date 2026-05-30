import SwiftUI

struct OnboardingView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var currentPage = 0
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if currentPage == 0 {
                    // Screen 1: Welcome
                    onboardingSlide(
                        title: t("Welcome to Sonor"),
                        description: t("Your personal, fast, and secure voice assistant. We're glad to have you on board."),
                        icon: "waveform.circle.fill",
                        color: .blue
                    ).transition(.opacity)
                } else if currentPage == 1 {
                    // Screen 2: Local & Privacy
                    onboardingSlide(
                        title: t("Total Privacy"),
                        description: t("Your data is safe. Everything happens locally on your device, ensuring maximum privacy and no data leaks."),
                        icon: "lock.shield.fill",
                        color: .green
                    ).transition(.opacity)
                } else if currentPage == 2 {
                    // Screen 3: Open Source
                    onboardingSlide(
                        title: t("Open Source"),
                        description: t("Sonor is built with transparency in mind. You can inspect the code and see exactly how it works under the hood."),
                        icon: "chevron.left.forwardslash.chevron.right",
                        color: .orange
                    ).transition(.opacity)
                } else if currentPage == 3 {
                    // Screen 4: Ready
                    onboardingSlide(
                        title: t("You're all set!"),
                        description: t("Let's get started and explore the possibilities of Sonor."),
                        icon: "sparkles",
                        color: .purple
                    ).transition(.opacity)
                }
            }
            .animation(.easeInOut, value: currentPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom Navigation
            HStack {
                if currentPage > 0 {
                    Button(action: {
                        withAnimation {
                            currentPage -= 1
                        }
                    }) {
                        Text(t("Previous"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Spacer to keep pagination centered
                    Text(t("Previous"))
                        .font(.system(size: 14, weight: .medium))
                        .opacity(0)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                
                Spacer()
                
                // Page Indicators
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: 8, height: 8)
                            .onTapGesture {
                                withAnimation {
                                    currentPage = index
                                }
                            }
                    }
                }
                
                Spacer()
                
                if currentPage < 3 {
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        Text(t("Next"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        withAnimation {
                            Task {
                                try? await AuthManager.shared.completeOnboarding()
                            }
                            onComplete()
                        }
                    }) {
                        Text(t("Let's Go!"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : Color.white)
    }
    
    @ViewBuilder
    private func onboardingSlide(title: String, description: String, icon: String, color: Color) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(color)
                .padding(32)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text(description)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}
