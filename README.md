# 🎙️ Sonor

> **Privacy-First, On-Device Voice Intelligence for macOS.**

Sonor is a modern, minimalist macOS application designed for high-performance voice-to-text transcription and intelligent text processing—running **100% locally and offline** on your device. Powered by `whisper.cpp` with Apple Silicon Metal acceleration and local LLMs (Gemma), your audio and data never leave your Mac.

---

## ✨ Key Features

* **Local-First & Privacy-First:** No cloud API endpoints, no data tracking, no external servers. Complete peace of mind.
* **Hardware Accelerated:** Deep integration with `whisper.cpp` optimized for Apple Silicon (M1/M2/M3/M4 chips) using Metal.
* **Model Manager:** Built-in dashboard to easily download, manage, and delete Whisper and Gemma models directly inside the app.
* **Productivity Suite:** Advanced history management (collapsible layouts), custom Snippets, AI Assistants, and custom Dictionaries.
* **Speech Analytics:** Track your voice metrics with real-time stats and an innovative Speech Tempo (WPM) chart.

## 🛠️ Tech Stack

* **Frontend:** Swift, SwiftUI (optimized for macOS, adopting a sleek Obsidian/Velvet Black theme)
* **Core Engine:** C++ (`whisper.cpp`, Gemma runtime)
* **Backend Framework:** Supabase (Secure user accounts & premium lifecycle)

---

## 🚀 Getting Started

### Prerequisites
* A Mac running macOS 13.0 or later (Apple Silicon highly recommended for GPU acceleration).

### Installation
1. Go to the **Releases** tab on GitHub.
2. Download the latest `Sonor.dmg` file.
3. Open the `.dmg` and drag Sonor to your `Applications` folder.
4. Launch the app and follow the onboarding flow to set up your account and download your first speech model via the **Model Manager**.

---

## 🔒 Privacy & Security

Sonor is engineered from the ground up to respect user privacy.
* Audio processing is computed directly via the Mac's GPU/Unified Memory.
* Account synchronization, localization safety checkboxes, and subscription checks are handled via encrypted Supabase connections.

---

## 🤝 Contributing

We welcome contributions from the open-source community! Whether you want to fix a bug, expand multi-language translations, or suggest new AI assistant flows:

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes using Conventional Commits (`git commit -m 'feat: Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Developed with ❤️ by <strong>Sonor Studio</strong>
</p>
