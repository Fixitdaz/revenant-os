# Over-The-Air (OTA) Update System

## Overview
Revenant OS includes a dedicated, self-updating Over-The-Air (OTA) utility (`revenant-update`) designed to synchronize the operating system, AI models, agent configurations, and hardware drivers over the internet without requiring fresh ISO re-installations.

---

## How to Run the Update

### Method 1: Standard Terminal Command (Channel-Aware)
If `revenant-update` is installed on your system:
```bash
sudo revenant-update
```

#### Dual Release Channels
Revenant OS features isolated release channels to ensure rock-solid stability while enabling rapid feature testing:
- **Stable Channel** (default):
  Tracks verified milestones (Build 17). Use this for mission-critical operations:
  ```bash
  sudo revenant-update --stable
  ```
- **Beta Channel**:
  Tracks bleeding-edge development features and field experiments before they are merged into the stable core:
  ```bash
  sudo revenant-update --beta
  ```
- **Persistent Channel Configuration**:
  Your selected channel is saved in `/etc/revenant/channel` and persists across updates and reboots.
- **Checking for Updates**:
  To inspect your active channel and compare your local build against upstream:
  ```bash
  sudo revenant-update --check
  ```
- **Forced Re-synchronization**:
  To force a complete re-download and re-configuration of all tiers regardless of version:
  ```bash
  sudo revenant-update --force
  ```

### Method 2: Direct One-Line Online Update
To pull the updater script directly from GitHub and execute it:
```bash
# For Stable channel:
curl -fsSL https://raw.githubusercontent.com/Fixitdaz/revenant-os/main/tools/revenant-update | sudo bash

# For Beta channel:
curl -fsSL https://raw.githubusercontent.com/Fixitdaz/revenant-os/beta/tools/revenant-update | sudo bash
```

---

## Autonomous Self-Updating Mechanism
Every time `revenant-update` is executed with an active internet connection, it performs an automatic integrity check against its active channel on GitHub (`main` or `beta`):
1. It queries the remote branch for changes to `tools/revenant-update`.
2. If an updated script exists, it downloads the script to `/usr/local/bin/revenant-update` and transparently re-executes itself.
3. This guarantees that installer fixes and newly added tiers are applied immediately.

---

## What the Updater Configures & Synchronizes

### Tier 0: Display Manager & Login Greeter
- Purges Debian live-config autologin overrides and Debian greeter configuration overrides.
- Ensures LightDM login greeter displays on startup with account selection and session switcher (XFCE and i3).
- De-brands default Debian login greeter: removes red swirl logo, applies the custom tactical Revenant **"R"** logo badge as avatar and logo, applies `revenant_bootsplash.png` background, and configures sleek Adwaita-dark aesthetic.

### Tier 1: Local Inference Engine (`llama-server`)
- Downloads static `llama-server` binary and `Qwen2.5-Coder-1.5B-Instruct` GGUF model if missing.
- Configures `llama-server.service` with a **4,096 token context window** and **unquantized `f16` Key-Value attention cache** (preventing memory pressure and repetition loops).
- Restarts and enables the service on `http://127.0.0.1:8080/v1`.

### Tier 2: Agent Stack, Memory & System Slimming
- Synchronizes Python packages for OpenInterpreter and OpenViking.
- Configures `openviking.service` automated context memory daemon.
- **System Slimming & Hardening**: Strips legacy background services, closes unused firewall ports, and reclaims memory (~350MB RAM) for 100% sovereign offline operation.
- Deploys the native **Revenant Custom Agent** (`/usr/local/bin/revenant-agent`) with real-time Toughbook telemetry, tool calling (`[EXEC]`, `[READ]`, `[WRITE]`), and voice commands (`/mic`, `/talk`, `/listen`).
- Configures environment variables in `/etc/environment` (`OPENAI_API_BASE` and `OPENAI_API_KEY`).

### Tier 3: Universal Terminal AI & Desktop Control
- Updates `/usr/local/bin/ai` for instant command-line prompting and `--mic` voice input queries. Running `ai` without arguments drops straight into the interactive Revenant Custom Agent.
- Deploys `/usr/local/bin/revenant-voice` instant voice agent launcher.
- Connects terminal AI responses to offline Piper neural text-to-speech.
- Deploys `Start_AI_Engine.desktop`, `Revenant_Agent.desktop`, and `Revenant_Voice.desktop` to user desktops.
- Deploys the `revenant-services` status monitor and launcher.

### Tier 3.5: Dual Desktop Environments, Dark Theme & Hotkeys
- Verifies that `i3`, `i3status`, `dmenu`, and wallpaper utilities are installed.
- Installs `/usr/local/bin/switch-to-i3` and `/usr/local/bin/switch-to-xfce` commands.
- **Desktop Clutter Cleanup**: Cleans up redundant `Switch_to_i3.desktop` and `Switch_to_XFCE.desktop` shortcuts from user desktops (the session selector on the LightDM login screen handles environment choice).
- **Global Voice Hotkey**: Configures `Super + M` (and `Ctrl + Alt + M`) to instantly pop open the floating Revenant Voice Assistant terminal.
- **Cyber Dark Theme & Obsidian Top Bar**: Sets `Adwaita-dark`, `Papirus-Dark`, and applies GTK3 CSS to transform the XFCE top panel into a solid obsidian black bar (`#0b0f17`) with crisp white/cyan text.
- Cleans up persistent autologin configurations in `/etc/lightdm/lightdm.conf.d/` so the LightDM greeter displays properly on boot, allowing user selection and session choice.

### Tier 4: Offline Neural Speech (Piper TTS)
- Verifies neural voice model files in `/opt/piper/models/` (`en_US-lessac-medium.onnx`).
- Downloads high-fidelity speech assets if missing.

### Tier 4.5: Offline Speech-to-Text (Whisper STT)
- Builds or installs `whisper.cpp` (`whisper-cli`) in `/opt/whisper/`.
- Downloads quantized `ggml-tiny.en.bin` model (~75MB) to `/opt/whisper/models/`.
- Configures ALSA `arecord` integration for 16kHz mono audio capture.
- Powers hands-free field agent interactions via `/mic` and `ai --mic`.

### Tier 5: Upstream Security, UFW Firewall & Kernel Drivers
- Detects Panasonic Toughbook chassis hardware and loads the `panasonic-laptop` module.
- Generates `/boot/config-*` kernel decompression flags to protect against `update-initramfs` decompression warnings.
- **Hardens System Firewall (UFW)**: Installs `ufw`, sets default deny incoming, default allow outgoing, allows SSH (`22/tcp`), and enables the firewall on boot.
- Runs non-interactive APT security upgrades and dependency cleanup.
- Updates the local version manifest in `/etc/revenant/version.json`.
