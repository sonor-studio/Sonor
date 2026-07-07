# 🎙️ Sonor

> **Privacy-First, On-Device Voice Intelligence for macOS.**

Sonor is a modern, minimalist macOS application designed for high-performance voice-to-text transcription and intelligent text processing—running **100% locally and offline** on your device. Powered by `whisper.cpp` with 
Apple Silicon Metal acceleration and local LLMs (Gemma), your audio and data never leave your Mac.

<img width="1280" height="720" alt="2" src="https://github.com/user-attachments/assets/98c5b5db-fe1a-44bf-9bf1-b4fb3ffd6e45" />

---

## ✨ Key Features

* **Local-First & Privacy-First:** No cloud API endpoints, no data tracking, no external servers. Complete peace of mind.
* **Hardware Accelerated:** Deep integration with `whisper.cpp` optimized for Apple Silicon (M1/M2/M3/M4 chips and newer) using Metal.
* **Model Manager:** Built-in dashboard to easily download, manage, and delete Whisper and Gemma models directly inside the app.
* **Productivity Suite:** Advanced history management (collapsible layouts), custom Snippets, Assistants, and custom Dictionaries.
* **Speech Analytics:** Track your voice metrics with real-time stats and an innovative Speaking Rate (WPM) chart.

<img width="1280" height="720" alt="6" src="https://github.com/user-attachments/assets/1bd1303f-2cdc-449d-b4f5-2da91c1bb1ec" />


## 🛠️ Tech Stack

* **Frontend:** Swift, SwiftUI (optimized for macOS)
* **Core Engine:** C++ (`whisper.cpp`, Gemma runtime)
* **Backend Framework:** Supabase (Secure user accounts & lifecycle management)

---

## 🚀 Getting Started

### Requirements
* **System:** macOS 14.6 or later.
* **Hardware:** Apple Silicon (M1/M2/M3/M4 chips and newer) **is strictly required** for local hardware acceleration. Intel processors are not supported.

### Installation & Gatekeeper Bypass
Because this is an independent open-source release without a paid Apple Developer certificate, macOS Gatekeeper will block the application on the first launch. Please follow these steps to run Sonor:

1. Go to the **Releases** tab on GitHub and download the latest `Sonor.dmg` file.
2. Open the `.dmg` and drag `Sonor.app` into your system **Applications** folder.
3. Double-click `Sonor.app` to trigger the initial system check. macOS will show a dialog stating it cannot be opened — click **Cancel**.
4. Open your macOS **System Settings** and navigate to **Privacy & Security**.
5. Scroll down to the *Security* section and click the **"Open Anyway"** button next to the Sonor block notice.
6. Confirm with your Mac password or Touch ID.

*Note: This configuration is a one-time process. Once approved, Sonor will launch instantly every time.*

<img width="1108" height="720" alt="1" src="https://github.com/user-attachments/assets/9d9e289b-eb32-45fb-af9a-d721cdef5a2d" />

---

## 🔒 Privacy & Security

Sonor is engineered from the ground up to respect user privacy.
* Audio processing is computed directly via the Mac's GPU/Unified Memory.
* Account synchronization and core analytics are securely handled via encrypted Supabase connections. No audio data or transcripts are ever transmitted.

---

## 🤝 Contributing

I welcome contributions from the open-source community! Whether you want to fix a bug, expand multi-language translations, or suggest new AI assistant flows:

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes using Conventional Commits (`git commit -m 'feat: Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License**. See the [LICENSE](LICENSE) file for more details.

---

<p align="center">
  Developed with ❤️ by <strong>Sonor Studio</strong>
</p>
