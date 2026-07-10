import SwiftUI
import AVFoundation
import AppKit
import Combine

struct PermissionsExplanationView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    @State private var hasAccessibility = false
    @State private var hasMicrophone = false
    
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Permissions Required"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            
            Text(t("Sonor requires the following permissions to function correctly. The application will be locked until all required permissions are granted."))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 20) {
                permissionRow(
                    icon: "mic.fill",
                    title: t("Microphone"),
                    description: t("Required to capture your voice for transcription."),
                    isGranted: hasMicrophone,
                    action: {
                        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in }
                        } else {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                )
                
                permissionRow(
                    icon: "figure.roll",
                    title: t("Accessibility"),
                    description: t("Required to automatically paste your transcribed text into other applications and support hotkeys."),
                    isGranted: hasAccessibility,
                    action: {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            
            Spacer()
        }
        .frame(width: 520, height: 400)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onAppear {
            checkPermissions()
        }
        .onReceive(timer) { _ in
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        let currentMic = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        if hasMicrophone != currentMic {
            hasMicrophone = currentMic
        }
        
        let currentAx = AXIsProcessTrusted()
        if hasAccessibility != currentAx {
            hasAccessibility = currentAx
        }
        
        if hasMicrophone && hasAccessibility {
            NotificationCenter.default.post(name: Notification.Name("HidePermissionViews"), object: nil)
        }
    }
    
    private func permissionRow(icon: String, title: String, description: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 24)
                
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .font(.system(size: 18))
                    .padding(.trailing, 8)
            } else {
                Button(action: action) {
                    Text(t("Open Settings"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .cornerRadius(10)
    }
}
