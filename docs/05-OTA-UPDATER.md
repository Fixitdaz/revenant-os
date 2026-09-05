# Over-The-Air (OTA) Update System

## Overview
Revenant OS includes a dedicated, self-updating Over-The-Air (OTA) utility (`revenant-update`) designed to synchronize the operating system, AI models, agent configurations, and hardware drivers over the internet without requiring fresh ISO re-installations.

---

## How to Run the Update

### Method 1: Standard Terminal Command
If `revenant-update` is installed on your system:
```bash
sudo revenant-update
```
To check for available updates without applying changes:
```bash
sudo revenant-update --check
```

### Method 2: Direct One-Line Online Update (Recommended for Instant Hotfixes)
To pull the very latest updater script directly from the repository and execute it immediately:
```bash
curl -fsSL https://raw.githubusercontent.com/Fixitdaz/revenant-os/main/tools/revenant-update | sudo bash
```

---

## Autonomous Self-Updating Mechanism
Every time `revenant-update` is executed with an active internet connection, it performs an automatic integrity check against GitHub:
1. It compares the local script against the upstream repository `main` branch.
2. If an updated updater script exists, it downloads the new script to `/usr/local/bin/revenant-update` and transparently re-executes itself.
3. This ensures bug fixes and new tiers are applied immediately without manual script downloads.

---

## What the Updater Configures & Synchronizes

### Tier 1: Local Inference Engine (`llama-server`)
- Downloads the static `llama-server` binary and `Qwen2.5-Coder-1.5B-Instruct` GGUF model if missing.
- Configures `llama-server.service` with a **20,480 token context window** and **unquantized `f16` Key-Value attention cache** (preventing 4-bit attention distortion and infinite text repetition).
- Restarts and enables the service on `http://127.0.0.1:8080/v1`.

### Tier 2: Agent Stack & Context Memory
- Synchronizes Python packages for OpenInterpreter and OpenViking.
- Configures `openviking.service` context memory daemon.
- Generates hardened Hermes Agent configuration (`~/.hermes/config.yaml`) with:
  - Custom provider name: `name: "local"`
  - 20,480 token context length
  - Auxiliary context compression model
- Sets system-wide environment variables in `/etc/environment` (`OPENAI_API_BASE` and `OPENAI_API_KEY`).

### Tier 3: Universal Terminal AI & Desktop Control
- Updates `/usr/local/bin/ai` for instant command-line prompting.
- Connects terminal AI responses to offline Piper neural text-to-speech.
- Deploys the `revenant-services` status monitor and desktop launcher.

### Tier 3.5: Dual Desktop Environments & Display Manager
- Verifies that `i3`, `i3status`, `dmenu`, and wallpaper utilities are installed.
- Installs `/usr/local/bin/switch-to-i3` and `/usr/local/bin/switch-to-xfce` commands.
- Adds desktop shortcuts (`Switch_to_i3.desktop` and `Switch_to_XFCE.desktop`) to user desktops.
- Cleans up persistent autologin configurations in `/etc/lightdm/lightdm.conf.d/` so the LightDM greeter displays properly on boot, allowing user selection and session choice.

### Tier 4: Offline Neural Speech (Piper TTS)
- Verifies neural voice model files in `/opt/piper/models/` (`en_US-lessac-medium.onnx`).
- Downloads high-fidelity speech assets if missing.

### Tier 5: Upstream Security & Kernel Driver Profiles
- Detects Panasonic Toughbook chassis hardware and loads the `panasonic-laptop` module.
- Generates `/boot/config-*` kernel decompression flags to protect against `update-initramfs` decompression warnings.
- Runs non-interactive APT security upgrades and dependency cleanup.
- Updates the local version manifest in `/etc/revenant/version.json`.
