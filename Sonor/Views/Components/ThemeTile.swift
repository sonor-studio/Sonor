import SwiftUI

struct ThemeTile: View {
    let title: String
    let theme: String
    @Binding var currentTheme: String
    
    var body: some View {
        let isSelected = currentTheme == theme
        
        Button(action: {
            currentTheme = theme
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(previewBgColor)
                    
                    HStack(spacing: 0) {
                        // Sidebar
                        Rectangle()
                            .fill(previewSidebarColor)
                            .frame(width: 40)
                            .overlay(
                                VStack(alignment: .leading, spacing: 6) {
                                    Circle().fill(previewTextColor.opacity(0.5)).frame(width: 10, height: 10)
                                    RoundedRectangle(cornerRadius: 2).fill(previewTextColor.opacity(0.3)).frame(width: 25, height: 4)
                                    RoundedRectangle(cornerRadius: 2).fill(previewTextColor.opacity(0.3)).frame(width: 20, height: 4)
                                    Spacer()
                                }
                                .padding(6)
                            )
                        
                        // Content
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(previewTextColor.opacity(0.1))
                                .frame(height: 15)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(previewTextColor.opacity(0.1))
                                .frame(height: 30)
                            Spacer()
                        }
                        .padding(10)
                    }
                }
                .frame(height: 100)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(15)
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var previewBgColor: Color {
        switch theme {
        case "light": return .white
        case "dark": return Color(red: 0.15, green: 0.15, blue: 0.15)
        case "system":
            let isSystemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return isSystemDark ? Color(red: 0.15, green: 0.15, blue: 0.15) : .white
        default: return .white
        }
    }
    
    private var previewSidebarColor: Color {
        switch theme {
        case "light": return Color(red: 0.9, green: 0.9, blue: 0.9)
        case "dark": return Color(red: 0.1, green: 0.1, blue: 0.1)
        case "system":
            let isSystemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return isSystemDark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color(red: 0.9, green: 0.9, blue: 0.9)
        default: return Color(red: 0.9, green: 0.9, blue: 0.9)
        }
    }
    
    private var previewTextColor: Color {
        switch theme {
        case "light": return .black
        case "dark": return .white
        case "system":
            let isSystemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return isSystemDark ? .white : .black
        default: return .white
        }
    }
}
