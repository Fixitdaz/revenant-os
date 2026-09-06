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
- Purges Debian live-config autologin overrides.
- Ensures LightDM login greeter displays on startup with account selection and session switcher (XFCE and i3).

### Tier 1: Local Inference Engine (`llama-server`)
- Downloads static `llama-server` binary and `Qwen2.5-Coder-1.5B-Instruct` GGUF model if missing.
- Configures `llama-server.service` with a **4,096 token context window** and **unquantized `f16` Key-Value attention cache** (preventing memory pressure and repetition loops).
- Restarts and enables the service on `http://127.0.0.1:8080/v1`.

### Tier 2: Agent Stack & Context Memory
- Synchronizes Python packages for OpenInterpreter and OpenViking.
- Configures `openviking.service` automated context memory daemon.
- System Slimming & Hardening: Strips legacy background services and ensures 100% sovereign offline operation.
- Deploys the native **Revenant Custom Agent** (`/usr/local/bin/revenant-agent`) with real-time Toughbook telemetry and tool calling (`[EXEC]`, `[READ]`, `[WRITE]`).
- Configures environment variables in `/etc/environment` (`OPENAI_API_BASE` and `OPENAI_API_KEY`).

### Tier 3: Universal Terminal AI & Desktop Control
- Updates `/usr/local/bin/ai` for instant command-line prompting. Running `ai` without arguments drops straight into the interactive Revenant Custom Agent.
- Connects terminal AI responses to offline Piper neural text-to-speech.
- Deploys `Start_AI_Engine.desktop` and `Revenant_Agent.desktop` to user desktops.
- Deploys the `revenant-services` status monitor and launcher.

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
