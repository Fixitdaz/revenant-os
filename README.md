# 💀 REVENANT OS (Agentic Core Edition)

> **Sovereign, Local-First Agentic AI Linux Operating System for Panasonic Toughbooks & Field Laptops**

[![Build Status](https://img.shields.io/badge/build-1.1_Build_18_Beta-00f0ff?style=for-the-badge&logo=linux)](https://github.com/Fixitdaz/revenant-os/tree/beta)
[![Target](https://img.shields.io/badge/Hardware-Panasonic_Toughbook_CF--52-ff007f?style=for-the-badge&logo=panasonic)](https://github.com/Fixitdaz/revenant-os)
[![Base](https://img.shields.io/badge/Kernel-Linux_6.1_Debian_Bookworm-purple?style=for-the-badge&logo=debian)](https://github.com/Fixitdaz/revenant-os)
[![Local Engine](https://img.shields.io/badge/Local_LLM-Qwen2.5--Coder--1.5B_via_llama--server-brightgreen?style=for-the-badge)](https://github.com/Fixitdaz/revenant-os)
[![Voice I/O](https://img.shields.io/badge/Voice-Whisper_STT_+_Piper_TTS-yellow?style=for-the-badge)](https://github.com/Fixitdaz/revenant-os)
[![Release Channels](https://img.shields.io/badge/Channels-Stable_&_Beta-blue?style=for-the-badge)](https://github.com/Fixitdaz/revenant-os)

> [!IMPORTANT]
> **Active Development & Work-in-Progress Disclaimer**  
> Revenant OS is currently under active development. While Build 17 is our stable production milestone, **Build 18 Beta** introduces full-duplex offline voice interaction (Whisper Speech-to-Text + Piper Text-to-Speech), complete Debian login screen de-branding, and system slimming (~350MB RAM reclaimed by purging legacy services and cloud proxies). New experimental features are isolated in the `beta` channel before promotion to stable.

---

## ⚡ Overview

**Revenant OS** is an autonomous, mission-hardened Linux distribution engineered specifically for rugged field computing on the **Panasonic Toughbook CF-52** (and compatible x86_64 field hardware). It transforms venerable, indestructible industrial laptops into local-first **Agentic AI workstations**.

Instead of relying on mandatory cloud subscriptions, external API keys, or accounts, Revenant OS embeds a native **offline inference server (`llama-server`)** paired with **Qwen2.5-Coder-1.5B-Instruct**, local **Whisper Speech-to-Text**, and the **OpenViking automated memory context database**. It operates 100% offline in remote environments, while offering seamless Over-The-Air (OTA) upgrades when connected to the internet with dedicated `--stable` and `--beta` channels.

---

## 🛠️ Key Capabilities & Features

### 1. 🧠 Built-In Offline Local Inference (Zero Account / Zero API Setup)
- **Embedded `llama-server` Daemon (`:8080`)**: Managed automatically by `systemd` (`llama-server.service`). Starts on boot and exposes standard OpenAI-compatible endpoints on `http://127.0.0.1:8080/v1`.
- **Pre-Bundled Model**: Loaded with `Qwen2.5-Coder-1.5B-Instruct` (Q4_K_M GGUF). Tuned for CPU execution on Toughbooks (runs fast at 8–14 tokens/sec, requiring only ~1.6 GB RAM).
- **4,096 Token Context Window**: Fast, low-latency 4K context length with pristine `f16` Key-Value attention cache, eliminating CPU cache thrashing and repetition loops.
- **Universal CLI (`ai <prompt>`)**: Simply type `ai "your query"` into any terminal to query the local model instantly, or run `ai --mic` to speak your query. Running `ai` with no arguments launches the interactive Revenant Custom Agent.
- **Full-Duplex Offline Voice (Whisper STT + Piper TTS)**: Spoken voice input transcribed locally via `whisper.cpp` (`tiny.en`), and agent responses spoken aloud through Toughbook speakers via neural Piper TTS.

### 2. 🧬 OpenViking Automated Context Memory
- Runs as an active background service (`openviking.service`) that automatically indexes terminal sessions, commands, notes, and preferences.
- Zero-token memory RAG: Subagents and CLI commands recall prior session contexts without massive token footprints.
- Queryable anytime via `ov ls viking://resources/` or `ov find "query"`.

### 3. 🤖 Autonomous Field Agents Ready Out-of-the-Box
- **Revenant Custom Agent (`revenant-agent`)**: A native, ultra-lightweight autonomous agent written in Python, engineered specifically for Toughbook dual-core CPUs:
  - **Tool Execution**: Directly inspects the system, executes bash commands (`[EXEC: ...]`), reads files (`[READ: ...]`), and writes files (`[WRITE: ...]`) with user confirmation safeguards.
  - **Live Hardware Telemetry**: Automatically displays battery percentage, CPU thermal temperatures, and RAM metrics in the header.
  - **Voice & Interactive Controls**: `/mic` (speak into Toughbook mic with instant Whisper STT transcription), `/voice` (toggle speech synthesis on/off), `/sys` (hardware diagnostics), and `/clear` (reset conversation memory).
  - **Global Hotkey (`Super + M`)**: Press `Super + M` (or `Ctrl + Alt + M`) anywhere on the desktop to immediately trigger the floating voice assistant.
  - Launch anytime via `revenant-voice`, `revenant-agent`, `revenant-agent --mic`, `ai`, or the desktop shortcuts.
- **OpenInterpreter**: Pre-configured in `/etc/environment` pointing to `http://127.0.0.1:8080/v1`. Inspects code, executes terminal commands, and edits files autonomously.
- **100% Sovereign Offline Footprint**: Completely self-contained offline architecture with zero external telemetry or cloud proxy dependencies. All inference, memory indexing, and speech recognition run 100% locally on device, saving ~350MB RAM.

### 4. 🖥️ Dual Desktop Environments: XFCE & i3
- **De-Branded LightDM Login**: Completely de-branded login screen featuring the custom `revenant_bootsplash.png` background, Adwaita-dark theme, and the cybernetic Revenant **"R"** logo badge replacing the Debian swirl.
- **Cyber Dark Theme & Obsidian Top Bar**: Full system dark theme (`Adwaita-dark`, `Papirus-Dark`) featuring a solid obsidian black panel (`#0b0f17`) with crisp white/cyan text and icons across the top of the screen.
- **i3 Tiling Window Manager**: Blazing-fast, purely keyboard-driven tiling window manager configured with instant terminal launching (`Mod+Enter`), application menus (`Mod+d`), workspace switching (`Mod+1..9`), and desktop status bars. Read the comprehensive [**i3 Beginner's Manual**](./docs/06-I3-USER-MANUAL.md).
- **Flexible Session Switching**:
  - **At Boot / Login**: The LightDM greeter provides an account selector and a session dropdown (top-right of screen) allowing you to choose between **Xfce Session** and **i3**.
  - **On-the-Fly Switching**: Run `switch-to-i3` or `switch-to-xfce` in any terminal to switch environments instantly without rebooting.

### 5. 🚜 Panasonic Toughbook CF-52 Hardware Hardening & Security
- **Hardened System Firewall (UFW)**: Pre-installed and active by default (`ufw status`). Configured to deny all unsolicited incoming connections while permitting outbound connections and SSH (`22/tcp`).
- **Legacy Graphics Acceleration**: Out-of-the-box configuration for Intel GMA 4500MHD / Intel HD graphics via `xserver-xorg-video-intel` and Mesa 3D DRI acceleration.
- **Toughbook Hotkey & Chassis Drivers**: Automatic loading of `panasonic-laptop` kernel driver for hotkeys, brightness controls, battery sensors, and thermal management.
- **Wireless Drivers**: Firmware for Intel PRO/Wireless & Centrino (`firmware-iwlwifi`), Atheros (`firmware-atheros`), Realtek, and Broadcom.
- **Audio Tuning**: Low-latency ALSA + PulseAudio mixer presets for Toughbook internal front stereo speakers and headphone jacks.
- **Power Management**: Pre-tuned `tlp` power saving profiles maximizing battery life in the field.

### 6. 🚀 Native Hard Drive Installer & Clean User Setup
- Graphical one-click installer (`/usr/local/bin/Install_Revenant_OS.sh`) on the live desktop.
- Automatically handles drive partitioning (MSDOS/MBR optimal alignment), ext4 formatting, file replication (`rsync -aAX`), user account creation, sudoers configuration, and native GRUB bootloader installation.
- Clean post-install boot: displays the LightDM login screen prompting for your created username and password (no stuck live `user` autologin).

### 7. 🔄 Over-The-Air (OTA) Dual-Channel Updates
- Keep installed Toughbooks updated over the internet without wiping or reinstalling using the built-in update utility:
  ```bash
  sudo revenant-update
  ```
- **Dual Release Channels**:
  - **Stable Channel** (default): Tracks tested milestone releases (Build 17):
    ```bash
    sudo revenant-update --stable
    ```
  - **Beta Channel**: Opt-in channel to test cutting-edge features before general release:
    ```bash
    sudo revenant-update --beta
    ```
- Your selected channel is saved in `/etc/revenant/channel` and persists across reboots and updates.
- Check update status anytime without applying changes:
  ```bash
  sudo revenant-update --check
  ```

---

## 🚀 Installation & Quick Start

1. **Download the ISO**:
   - **Stable**: `revenant_os_1.0_build17.iso` (Verified production release)
   - **Beta**: `revenant_os_1.1_build18_beta.iso` (Cutting-edge voice STT & debranded)
2. **Flash to USB**:
   - **Windows**: Use [Rufus](https://rufus.ie/) in *DD Mode* or [BalenaEtcher](https://etcher.balena.io/).
   - **Linux / macOS**:
     ```bash
     sudo dd if=revenant_os_1.1_build18_beta.iso of=/dev/sdX bs=4M status=progress conv=fsync
     ```
3. **Boot on Panasonic Toughbook CF-52**:
   - Insert USB into Toughbook USB port.
   - Power on the laptop and tap `F2` to enter the BIOS Setup Utility.
   - Navigate to the **Boot** menu, move your **USB Drive / USB HDD** to the top of the boot order, press `F10` to save and exit.
4. **Install to Internal Storage**:
   - Once on the live desktop, double-click **"Install Revenant OS"**.
   - Enter your username, password, hostname, and select your target drive (e.g. `/dev/sda`).
   - Click **"Yes, Erase & Install"**. Once completed, reboot and remove the USB stick.
5. **Log In & Select Session**:
   - At the login screen, select your username, enter your password, and choose **Xfce Session** or **i3** from the top session dropdown.

---

## 📚 Documentation & Wiki

Explore our dedicated documentation in the [`docs/`](./docs) directory:

- [**01: Getting Started & Boot Guide**](./docs/01-GETTING-STARTED.md) - USB flashing, Toughbook BIOS setup, and live installation.
- [**02: Agentic AI Core & Local LLM Manual**](./docs/02-AGENT-STACK.md) - llama-server, Qwen2.5 local model (4K context), OpenViking memory daemon, and agent orchestration.
- [**03: Dual Desktop Environments**](./docs/03-DESKTOP-ENVIRONMENTS.md) - Using XFCE, mastering the i3 window manager, and switching sessions.
- [**04: Toughbook Hardware Optimization**](./docs/04-HARDWARE-OPTIMIZATION.md) - Hotkeys, battery tuning, and display drivers.
- [**05: Over-The-Air (OTA) Updates**](./docs/05-OTA-UPDATER.md) - Updating installed systems over the air.
- [**06: i3 Window Manager Beginner's Manual**](./docs/06-I3-USER-MANUAL.md) - Jargon-free guide, visual splitting diagrams, workflows, and complete keybinding cheat sheet.

---

## 🛡️ License

Revenant OS configuration files, build scripts, and custom integrations are released under the **MIT License**. Third-party Linux kernel components and upstream packages are governed by their respective licenses (GPL, Apache, BSD).
