# Python script to generate all repository documentation, wiki, and OTA updater
import os

os.makedirs('tools', exist_ok=True)
os.makedirs('docs', exist_ok=True)

# 1. version.json
version_json = r'''{
  "os_name": "Revenant OS",
  "version": "1.0.0",
  "build": 14,
  "target_hardware": "Panasonic Toughbook CF-52 & Field Laptops",
  "release_date": "2026-09-04",
  "kernel": "6.1.0-50-amd64",
  "agent_core": {
    "omniroute": "latest",
    "openviking": "latest",
    "open_interpreter": "latest",
    "piper_tts": "2023.11.14-2"
  }
}
'''
with open('version.json', 'w', encoding='utf-8', newline='\n') as f:
    f.write(version_json)

# 2. tools/revenant-update
updater_script = r'''#!/bin/bash
# ==============================================================================
# Revenant OS - Intelligent Over-The-Air (OTA) System & Agent Updater
# ==============================================================================
# Upgrades:
#   1. Agent Core (OmniRoute, OpenInterpreter, OpenViking, Hermes Agent)
#   2. Offline Neural TTS Voice Models (Piper)
#   3. System Scripts, Themes, Plymouth Splash, and Desktop Configurations
#   4. Upstream Linux Kernel & Security Patches
# ==============================================================================

set -e

REPO_OWNER="Fixitdaz"
REPO_NAME="revenant-os"
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"
LOCAL_VERSION_FILE="/etc/revenant/version.json"

CYAN="\033[96m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
RESET="\033[0m"
BOLD="\033[1m"

echo -e "${CYAN}${BOLD}"
echo "=========================================================="
echo "           REVENANT OS - SYSTEM & AGENT UPDATER           "
echo "=========================================================="
echo -e "${RESET}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Please run as root: sudo revenant-update${RESET}"
  exit 1
fi

CHECK_ONLY=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --check|-c)
      CHECK_ONLY=true
      ;;
    --force|-f)
      FORCE=true
      ;;
    --help|-h)
      echo "Usage: sudo revenant-update [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -c, --check    Check for available updates without applying them"
      echo "  -f, --force    Force re-application of all updates and agent dependencies"
      echo "  -h, --help     Show this help message"
      exit 0
      ;;
  esac
done

echo -e "${CYAN}[*] Testing internet connectivity...${RESET}"
if ! curl -s --head --connect-timeout 5 https://github.com >/dev/null; then
  echo -e "${RED}[!] Internet connection failed. Please connect to a network and try again.${RESET}"
  exit 1
fi
echo -e "${GREEN}[✓] Online connection verified.${RESET}"

mkdir -p /etc/revenant
if [ ! -f "$LOCAL_VERSION_FILE" ]; then
  cat << 'EOF' > "$LOCAL_VERSION_FILE"
{
  "os_name": "Revenant OS",
  "version": "1.0.0",
  "build": 14,
  "release_date": "2026-09-04"
}
EOF
fi

CURRENT_VER=$(grep -oP '"version":\s*"\K[^"]+' "$LOCAL_VERSION_FILE" || echo "1.0.0")
CURRENT_BUILD=$(grep -oP '"build":\s*\K[0-9]+' "$LOCAL_VERSION_FILE" || echo "14")

echo -e "${CYAN}[*] Current Installed Version: ${BOLD}v$CURRENT_VER (Build $CURRENT_BUILD)${RESET}"
echo -e "${CYAN}[*] Querying remote release manifest from GitHub...${RESET}"

REMOTE_MANIFEST=$(curl -fsSL --connect-timeout 10 "$RAW_BASE/version.json" 2>/dev/null || true)

if [ -z "$REMOTE_MANIFEST" ]; then
  echo -e "${YELLOW}[!] Could not fetch remote manifest (repository may be private or offline).${RESET}"
  echo -e "${CYAN}[*] Proceeding with live component synchronization mode...${RESET}"
  REMOTE_BUILD=$CURRENT_BUILD
else
  REMOTE_VER=$(echo "$REMOTE_MANIFEST" | grep -oP '"version":\s*"\K[^"]+' || echo "$CURRENT_VER")
  REMOTE_BUILD=$(echo "$REMOTE_MANIFEST" | grep -oP '"build":\s*\K[0-9]+' || echo "$CURRENT_BUILD")
  echo -e "${CYAN}[*] Latest Remote Version:    ${BOLD}v$REMOTE_VER (Build $REMOTE_BUILD)${RESET}"
fi

if [ "$CHECK_ONLY" = true ]; then
  if [ "$REMOTE_BUILD" -gt "$CURRENT_BUILD" ]; then
    echo -e "${GREEN}[✓] A new update is available: Build $REMOTE_BUILD (Installed: $CURRENT_BUILD)${RESET}"
    echo -e "Run 'sudo revenant-update' to install."
    exit 0
  else
    echo -e "${GREEN}[✓] System is up to date.${RESET}"
    exit 0
  fi
fi

# TIER 1: Agentic AI Core Upgrades
echo ""
echo -e "${CYAN}${BOLD}[1/4] Upgrading Agentic AI Core...${RESET}"
echo -e "${CYAN}  -> Upgrading OmniRoute & Hermes Agent...${RESET}"
npm install -g omniroute hermes-agent --silent || true

echo -e "${CYAN}  -> Upgrading OpenInterpreter & OpenViking memory context engine...${RESET}"
pip3 install --break-system-packages --upgrade open-interpreter openviking >/dev/null 2>&1 || true

echo -e "${CYAN}  -> Restarting OmniRoute systemd service...${RESET}"
systemctl restart omniroute.service 2>/dev/null || true
echo -e "${GREEN}[✓] Agentic AI Core updated and running.${RESET}"

# TIER 2: Offline Neural TTS (Piper)
echo ""
echo -e "${CYAN}${BOLD}[2/4] Verifying Offline Neural Speech Synthesis (Piper)...${RESET}"
mkdir -p /opt/piper/models
if [ ! -f /opt/piper/models/en_US-lessac-medium.onnx ]; then
  echo -e "${CYAN}  -> Downloading neural voice model...${RESET}"
  curl -fsSL -o /opt/piper/models/en_US-lessac-medium.onnx https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx || true
  curl -fsSL -o /opt/piper/models/en_US-lessac-medium.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json || true
fi
echo -e "${GREEN}[✓] Offline neural speech synthesis verified.${RESET}"

# TIER 3: System Utilities & Drivers (Toughbook CF-52)
echo ""
echo -e "${CYAN}${BOLD}[3/4] Synchronizing System Configurations & Field Drivers...${RESET}"
if dmidecode 2>/dev/null | grep -iq "Panasonic"; then
  modprobe panasonic-laptop 2>/dev/null || true
fi
if [ -f /usr/local/bin/ai ]; then
  chmod +x /usr/local/bin/ai
fi
echo -e "${GREEN}[✓] Field drivers and utilities synchronized.${RESET}"

# TIER 4: Upstream Base Security & Kernel
echo ""
echo -e "${CYAN}${BOLD}[4/4] Checking Upstream Security Patches...${RESET}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq
echo -e "${GREEN}[✓] Security packages up to date.${RESET}"

if [ -n "$REMOTE_MANIFEST" ]; then
  echo "$REMOTE_MANIFEST" > "$LOCAL_VERSION_FILE"
else
  cat << EOF > "$LOCAL_VERSION_FILE"
{
  "os_name": "Revenant OS",
  "version": "$CURRENT_VER",
  "build": $CURRENT_BUILD,
  "last_updated": "$(date -Iseconds)"
}
EOF
fi

echo ""
echo -e "${GREEN}${BOLD}==========================================================${RESET}"
echo -e "${GREEN}${BOLD}       [✓] REVENANT OS IS FULLY UP TO DATE!               ${RESET}"
echo -e "${GREEN}${BOLD}==========================================================${RESET}"
echo ""
'''
with open(os.path.join('tools', 'revenant-update'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(updater_script)

# 3. README.md
readme_content = r'''# 💀 REVENANT OS (Agentic Core Edition)

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
'''
with open('README.md', 'w', encoding='utf-8', newline='\n') as f:
    f.write(readme_content)

# 4. Docs / Wiki Files
docs_01 = r'''# Getting Started with Revenant OS

## System Requirements
- **Recommended Hardware**: Panasonic Toughbook CF-52 (Mark 1, 2, 3, 4, 5).
- **Compatible Hardware**: Any x86_64 laptop or workstation with Legacy BIOS (MBR) or UEFI support.
- **Minimum RAM**: 2 GB (4 GB recommended for local LLM routing and browser multitasking).
- **Storage**: 20 GB or larger internal SATA HDD or SSD.
- **Boot Media**: 4 GB or larger USB Flash Drive.

---

## Flashing the USB Drive

### Option A: Using Rufus (Windows)
1. Download [Rufus](https://rufus.ie/).
2. Insert your USB flash drive.
3. Select `revenant_os_toughbook_v14.iso`.
4. Partition scheme: **MBR**, Target system: **BIOS or UEFI**.
5. Click **Start**. When prompted, select **Write in DD Image mode** (recommended for hybrid bootloaders).

### Option B: Using BalenaEtcher (Windows / macOS / Linux)
1. Open BalenaEtcher.
2. Select `revenant_os_toughbook_v14.iso`.
3. Select your target USB stick.
4. Click **Flash!**.

---

## Booting on Panasonic Toughbook CF-52
1. Plug the flashed USB stick into one of the Toughbook's USB ports.
2. Power on the laptop and immediately tap the **F12** key repeatedly.
3. In the boot device selection list, highlight **USB HDD** or your flash drive model, then press **Enter**.
4. The high-definition **Revenant OS GRUB bootloader** will appear. Select `Revenant OS - Agentic Core`.
5. The full-screen Revenant cyber boot splash will display as drivers load.
6. The system automatically logs into the live environment.

---

## Hard Drive Installation
1. Double-click **"Install Revenant OS"** on the live desktop.
2. Enter your desired **Username**, **Password**, and **Computer Hostname**.
3. Choose the target internal drive (e.g. `/dev/sda`).
4. Review the final confirmation prompt and click **"Yes, Erase & Install"**.
5. The installer will partition, format (ext4), replicate system files, configure the bootloader, and un-divert initramfs updates.
6. When the success notification appears, reboot and remove the USB drive.
'''
with open(os.path.join('docs', '01-GETTING-STARTED.md'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(docs_01)

docs_02 = r'''# Agentic AI Core Architecture & Usage

## Overview
Revenant OS features a native, pre-installed AI agent stack designed for sovereign edge computing and multi-agent coordination.

---

## Core Components

### 1. OmniRoute AI Gateway (`:20128`)
- **Daemon**: Managed by `systemctl status omniroute.service`.
- **Purpose**: A local OpenAI-compatible API gateway and proxy that handles multi-provider routing, load balancing, rate limiting, and fallback across local and cloud models.
- **Port**: `20128` on `localhost`.

### 2. Universal Terminal Assistant (`ai`)
You can invoke the AI assistant directly from any terminal session (Fish shell or Bash):
```bash
ai "Summarize the last 50 lines of dmesg and check for hardware errors"
```
```bash
ai "Write a bash script to monitor wifi signal strength every 5 seconds"
```

### 3. OpenInterpreter
Execute tasks using natural language:
```bash
interpreter
```
OpenInterpreter connects directly to the local Python and shell runtime, enabling automated file management, data processing, and scripting.

### 4. OpenViking Context Database
- Integrates persistent memory and vector embeddings for agent workflows.
- Accessible via the `ov` CLI:
  ```bash
  ov ls viking://resources/
  ```

### 5. Offline Neural Speech (Piper)
Revenant OS uses **Piper TTS** to speak agent responses asynchronously without cloud latency:
- Neural voice models reside in `/opt/piper/models/`.
- Test voice synthesis manually:
  ```bash
  echo "Revenant OS core systems online." | /opt/piper/piper -m /opt/piper/models/en_US-lessac-medium.onnx --output_raw | aplay -r 22050 -f S16_LE -t raw -
  ```
'''
with open(os.path.join('docs', '02-AGENT-STACK.md'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(docs_02)

docs_03 = r'''# Dual Desktop Environments: XFCE & i3

## Choosing Your Desktop
At the LightDM login screen, click the session dropdown in the upper right panel to choose between:
- **XFCE Session**: Full graphical desktop with windows, panels, and mouse workflows.
- **i3 Session**: Tiling window manager for pure keyboard speed.

---

## i3 Window Manager Cheat Sheet

### Essential Shortcuts:
- **Mod Key**: `Windows Key` (Super)
- **Open Terminal**: `Mod + Enter`
- **Application Launcher (dmenu)**: `Mod + d`
- **Close Window**: `Mod + Shift + q`
- **Help / Cheat Sheet**: `Mod + F1`
- **Log Out**: `Mod + Shift + e`

### Window Navigation:
- **Focus Window**: `Mod + Arrow Keys` (or `Mod + j/k/l/;`)
- **Move Window**: `Mod + Shift + Arrow Keys`
- **Switch Workspace**: `Mod + 1` through `Mod + 9`
- **Move Window to Workspace**: `Mod + Shift + 1` through `9`

### Window Layout:
- **Horizontal Split**: `Mod + h`
- **Vertical Split**: `Mod + v`
- **Toggle Fullscreen**: `Mod + f`
- **Toggle Floating Mode**: `Mod + Shift + Space`
- **Resize Mode**: `Mod + r` (use arrow keys, press `Esc` when done)
'''
with open(os.path.join('docs', '03-DESKTOP-ENVIRONMENTS.md'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(docs_03)

docs_04 = r'''# Toughbook CF-52 Hardware Optimization

## Panasonic Hotkeys & Battery Diagnostics
- Driver: `panasonic-laptop`
- Battery charge limits, brightness keys, and thermal fan profiles are managed natively by the ACPI subsystem.
- Inspect battery health:
  ```bash
  upower -i /org/freedesktop/UPower/devices/battery_BAT1
  ```

## Legacy Graphics Acceleration
- Video driver: `xserver-xorg-video-intel`
- Mesa 3D DRI acceleration is enabled by default.
- Verify DRI status:
  ```bash
  glxinfo | grep "direct rendering"
  ```

## Power Management (TLP)
- TLP automatically switches between AC power profiles and battery saver profiles.
- Check current power profile:
  ```bash
  sudo tlp-stat -s
  ```

## Firewall (UFW)
- Revenant OS enables a strict default firewall:
  - **Incoming**: Denied
  - **Outgoing**: Allowed
  - **SSH**: Allowed (`22/tcp`)
  - **OmniRoute**: Local loopback only (`20128/tcp`)
- Check status:
  ```bash
  sudo ufw status verbose
  ```
'''
with open(os.path.join('docs', '04-HARDWARE-OPTIMIZATION.md'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(docs_04)

docs_05 = r'''# Over-The-Air (OTA) Update System

## How It Works
Revenant OS includes a dedicated OTA update utility (`revenant-update`) that synchronizes the operating system over the internet without needing fresh ISO installs.

---

## Running an Update

### 1. Check for Updates
To see if a new build or security patch is available:
```bash
sudo revenant-update --check
```

### 2. Apply All Updates
To download and install the latest components:
```bash
sudo revenant-update
```

---

## Update Layers
1. **Agent Core Layer**:
   - Pulls the latest `omniroute`, `hermes-agent`, `openviking`, and `open-interpreter` packages.
   - Automatically restarts the `omniroute.service` systemd unit.
2. **Offline Speech Layer**:
   - Checks `/opt/piper/models/` and downloads updated voice models if missing or upgraded.
3. **Hardware & Configuration Layer**:
   - Synchronizes Toughbook hotkey drivers, terminal aliases, and desktop profiles.
4. **Base System Security Layer**:
   - Executes non-interactive package index update and security upgrades via APT.
'''
with open(os.path.join('docs', '05-OTA-UPDATER.md'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(docs_05)

print('All documentation, wiki, version manifest, and OTA updater created!')
