# 💀 REVENANT OS (Agentic Core Edition)

> **Sovereign, Air-Gapped Agentic AI Linux Operating System for Panasonic Toughbooks & Field Laptops**

[![Build Status](https://img.shields.io/badge/build-v14_pass-00f0ff?style=for-the-badge&logo=linux)](https://github.com/Fixitdaz/revenant-os)
[![Target](https://img.shields.io/badge/Hardware-Panasonic_Toughbook_CF--52-ff007f?style=for-the-badge&logo=panasonic)](https://github.com/Fixitdaz/revenant-os)
[![Base](https://img.shields.io/badge/Kernel-Linux_6.1_Debian_Bookworm-purple?style=for-the-badge&logo=debian)](https://github.com/Fixitdaz/revenant-os)
[![Agent Gateway](https://img.shields.io/badge/AI_Core-OmniRoute_+_OpenInterpreter-brightgreen?style=for-the-badge)](https://github.com/Fixitdaz/revenant-os)

---

## ⚡ Overview

**Revenant OS** is an autonomous, mission-hardened Linux distribution engineered specifically for rugged field computing on the **Panasonic Toughbook CF-52** (and compatible x86_64 field hardware). It transforms venerable, indestructible industrial laptops into local-first **Agentic AI workstations**.

Unlike standard distributions, Revenant OS completely discards legacy branding in favor of a sleek, dark cyberpunk visual identity, complete with full-screen Plymouth boot graphics, an integrated local LLM routing gateway, offline neural voice synthesis, and dual graphical/tiling desktops.

---

## 🛠️ Key Capabilities & Features

### 1. 🧠 Integrated Local Agentic Core
- **OmniRoute Gateway (`:20128`)**: Built-in local OpenAI-compatible API reverse proxy and intelligent router running as a hardened systemd background daemon (`omniroute.service`). Routes agent prompts seamlessly across local and cloud providers.
- **OpenInterpreter**: Native terminal integration allowing local AI agents to write and execute code, analyze logs, inspect hardware, and automate local workflows.
- **OpenViking**: Self-evolving automated context memory and persistent knowledge RAG database for AI agent sessions.
- **Hermes Agent**: Autonomous role-based agent stack ready for complex task delegation.
- **Universal CLI (`ai <prompt>`)**: Simply type `ai "your query"` into any shell to query the local Agent Core.

### 2. 🗣️ Offline Neural Speech Synthesis (Piper TTS)
- Pre-loaded with **Piper neural text-to-speech** models (`en_US-lessac-medium.onnx`).
- Zero internet dependency: Voice synthesis is calculated locally on CPU using optimized ONNX runtimes and piped directly to ALSA/PulseAudio.
- Asynchronous speech delivery: `ai` CLI speaks responses aloud without blocking the terminal.

### 3. 🌐 Sovereign Web Experience (Vivaldi Only)
- Pre-configured with the **Vivaldi Browser** exclusively.
- All extraneous browsers (Chromium, Firefox, Epiphany) have been eradicated to maintain lightweight resource overhead and eliminate telemetry.
- Built-in tracking protection, ad blocking, and tab-tiling for multi-document research.

### 4. 🖥️ Dual Desktop Environments
- **XFCE Desktop**: Polished, low-footprint traditional desktop with custom Revenant cyber wallpaper, customized panel dock, and graphical administration tools.
- **i3 Tiling Window Manager**: Blazing-fast, purely keyboard-driven tiling window manager configured with instant terminal launching (`Mod+Enter`), application menus (`Mod+d`), workspace switching (`Mod+1..9`), and desktop status bars.
- Switch between environments instantly from the LightDM display manager session selector.

### 5. 🚜 Panasonic Toughbook CF-52 Hardware Hardening
- **Legacy Graphics Acceleration**: Out-of-the-box configuration for Intel GMA 4500MHD / Intel HD graphics via `xserver-xorg-video-intel` and Mesa 3D DRI acceleration.
- **Toughbook Hotkey & Chassis Drivers**: Automatic loading of `panasonic-laptop` kernel driver for hotkeys, brightness controls, battery sensors, and thermal management.
- **Wireless Drivers**: Firmware for Intel PRO/Wireless & Centrino (`firmware-iwlwifi`), Atheros (`firmware-atheros`), Realtek, and Broadcom.
- **Audio Tuning**: Low-latency ALSA + PulseAudio mixer presets for Toughbook internal front stereo speakers and headphone jacks.
- **Power Management**: Pre-tuned `tlp` power saving profiles maximizing battery life in the field.

### 6. 🚀 Bespoke Native Hard Drive Installer
- Graphical one-click installer (`/usr/local/bin/Install_Revenant_OS.sh`) on the live desktop.
- Automatically handles drive partitioning (MSDOS/MBR optimal alignment), ext4 formatting, file replication (`rsync -aAX`), user account creation, sudoers configuration, and native GRUB bootloader installation.

### 7. 🔄 Over-The-Air (OTA) Updating
- Keep installed Toughbooks updated over the internet without wiping or reinstalling using the built-in update utility:
  ```bash
  sudo revenant-update
  ```
- Automatically pulls latest AI agent updates, Piper speech models, driver updates, and security patches from GitHub.

---

## 🚀 Installation & Quick Start

1. **Download the ISO**: Get the latest build (`revenant_os_toughbook_v14.iso`).
2. **Flash to USB**:
   - **Windows**: Use [Rufus](https://rufus.ie/) in *DD Mode* or [BalenaEtcher](https://etcher.balena.io/).
   - **Linux / macOS**:
     ```bash
     sudo dd if=revenant_os_toughbook_v14.iso of=/dev/sdX bs=4M status=progress conv=fsync
     ```
3. **Boot on Panasonic Toughbook CF-52**:
   - Insert USB into Toughbook USB port.
   - Power on and tap `F12` to open the BIOS Boot Selection Menu.
   - Select your USB drive and press `Enter`.
4. **Install to Internal Storage**:
   - Once on the desktop, double-click **"Install Revenant OS"**.
   - Select your target drive (e.g. `/dev/sda`), enter your desired username/password, and confirm.
   - Once complete, reboot and remove the USB stick.

---

## 📚 Documentation & Wiki

Explore our dedicated documentation in the [`docs/`](./docs) directory:

- [**01: Getting Started & Boot Guide**](./docs/01-GETTING-STARTED.md) - USB flashing, Toughbook BIOS setup, and live boot.
- [**02: Agentic AI Core Manual**](./docs/02-AGENT-STACK.md) - OmniRoute, OpenInterpreter, OpenViking, and custom agent prompts.
- [**03: Dual Desktop Environments**](./docs/03-DESKTOP-ENVIRONMENTS.md) - Using XFCE and mastering the i3 window manager.
- [**04: Toughbook Hardware Optimization**](./docs/04-HARDWARE-OPTIMIZATION.md) - Hotkeys, battery tuning, and touchscreen calibration.
- [**05: Over-The-Air (OTA) Updates**](./docs/05-OTA-UPDATER.md) - Updating installed systems over the internet.

---

## 🛡️ License

Revenant OS configuration files, build scripts, and custom integrations are released under the **MIT License**. Third-party Linux kernel components and upstream packages are governed by their respective licenses (GPL, Apache, BSD).
