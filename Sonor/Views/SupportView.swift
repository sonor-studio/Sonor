import SwiftUI

struct SupportView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appTheme") private var appTheme = "system"
    @ObservedObject var localizer = LocalizationManager.shared
    var onClose: () -> Void
    
    @State private var showQRCode = false
    
    var effectiveColorScheme: ColorScheme {
        if appTheme == "dark" {
            return .dark
        } else if appTheme == "light" {
            return .light
        } else {
            let appleInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            return appleInterfaceStyle == "Dark" ? .dark : .light
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Górny odstęp
            Spacer()
                .frame(height: 25)
            
            if showQRCode {
                // Widok Kodu QR (po kliknięciu Zeskanuj QR)
                VStack(spacing: 16) {
                    // Ikona i Tytuł
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 38))
                            .foregroundColor(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text(t("Scan QR Code"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Bezpieczne wczytywanie obrazka QR z lokalnych zasobów
                    if let image = NSImage(contentsOfFile: "/Users/macbook/Desktop/Dev/Sonor/Sonor/Resources/qr-code.png") {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                            .cornerRadius(12)
                            .shadow(color: Color.primary.opacity(0.15), radius: 8, x: 0, y: 4)
                    } else if let bundlePath = Bundle.main.path(forResource: "qr-code", ofType: "png"), let image = NSImage(contentsOfFile: bundlePath) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                            .cornerRadius(12)
                            .shadow(color: Color.primary.opacity(0.15), radius: 8, x: 0, y: 4)
                    } else {
                        Image(systemName: "qrcode")
                            .resizable()
                            .frame(width: 160, height: 160)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(t("Scan the code with your phone to buy me a coffee on Buy Me a Coffee."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Przycisk wstecz
                    Button(action: {
                        withAnimation {
                            showQRCode = false
                        }
                    }) {
                        Text(t("Back"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(effectiveColorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(effectiveColorScheme == .dark ? Color.white : Color.black)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                // Główny widok wsparcia
                VStack(spacing: 0) {
                    // Ikona i Tytuł
                    VStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 38))
                            .foregroundColor(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text(t("Do you like Sonor?"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(.bottom, 24)
                    
                    // Treść strukturalna (3 czytelne punkty)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(effectiveColorScheme == .dark ? .white : .black)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Local and Free"))
                                    .font(.system(size: 12, weight: .bold))
                                Text(t("Transcription and text cleaning work 100% locally on your Mac — your data is completely secure."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(effectiveColorScheme == .dark ? .white : .black)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Apple Certification"))
                                    .font(.system(size: 12, weight: .bold))
                                Text(t("I am raising funds for the annual Apple Developer Account fee so the app can be officially signed and easier to install."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(effectiveColorScheme == .dark ? .white : .black)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Support the Creator"))
                                    .font(.system(size: 12, weight: .bold))
                                Text(t("If Sonor saves you time and you appreciate my work, you can buy me a virtual coffee. Every little bit helps!"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    // Przyciski akcji (Minimalistyczny motyw Black & White)
                    VStack(spacing: 8) {
                        // Kup kawę (Przycisk Główny z nowym linkiem)
                        Button(action: {
                            if let url = URL(string: "https://buymeacoffee.com/sonorstudio") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text(t("Buy a Coffee ☕️"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(effectiveColorScheme == .dark ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(effectiveColorScheme == .dark ? Color.white : Color.black)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        
                        // Zeskanuj QR (Przycisk wtórny z obramowaniem)
                        Button(action: {
                            withAnimation {
                                showQRCode = true
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 12, weight: .bold))
                                Text(t("Scan QR Code"))
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .frame(width: 360, height: 440)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(effectiveColorScheme)
    }
}
