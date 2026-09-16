#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_rebuild_1_1"
PATCH_ROOT="/var/tmp/patch_root_1_1"
ISO_SOURCE="$SCRIPT_DIR/revenant_os_toughbook_v15_5.iso"
ISO_TARGET="$SCRIPT_DIR/revenant_os_1.1_build19.8.iso"
ISO_ALIAS="$SCRIPT_DIR/revenant_os_latest.iso"
CACHE_DIR="/var/tmp/revenant_cache"

echo "[*] Cleaning up previous mounts and temporary directories..."
umount /mnt/iso 2>/dev/null || true
umount "$PATCH_ROOT/proc" 2>/dev/null || true
umount "$PATCH_ROOT/sys" 2>/dev/null || true
umount "$PATCH_ROOT/dev/pts" 2>/dev/null || true
umount "$PATCH_ROOT/dev" 2>/dev/null || true
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"
mkdir -p "$CACHE_DIR"

echo "[*] Mounting source ISO..."
mkdir -p /mnt/iso
mount -o loop,ro "$ISO_SOURCE" /mnt/iso

echo "[*] Unpacking SquashFS root..."
unsquashfs -d "$PATCH_ROOT" /mnt/iso/live/filesystem.squashfs

echo "[*] Setting up ISO base image tree..."
mkdir -p "$WORKSPACE_DIR/image/live" "$WORKSPACE_DIR/image/boot/grub"
cp /mnt/iso/live/vmlinuz "$WORKSPACE_DIR/image/live/vmlinuz"
cp /mnt/iso/live/initrd.img "$WORKSPACE_DIR/image/live/initrd.img"
if [ -f "$SCRIPT_DIR/revenant_bootsplash.png" ]; then
  cp "$SCRIPT_DIR/revenant_bootsplash.png" "$WORKSPACE_DIR/image/boot/grub/splash.png"
elif [ -f /mnt/iso/boot/grub/splash.png ]; then
  cp /mnt/iso/boot/grub/splash.png "$WORKSPACE_DIR/image/boot/grub/splash.png"
fi

echo "[*] Unmounting source V15.1 ISO..."
umount /mnt/iso

echo "[*] Installing Toughbook hardware support, Bitwarden, and extra utilities..."
mount --bind /proc "$PATCH_ROOT/proc"
mount --bind /sys "$PATCH_ROOT/sys"
mount --bind /dev "$PATCH_ROOT/dev"
mount --bind /dev/pts "$PATCH_ROOT/dev/pts"
cp /etc/resolv.conf "$PATCH_ROOT/etc/resolv.conf"

export DEBIAN_FRONTEND=noninteractive
rm -f "$PATCH_ROOT/var/lib/apt/lists/lock" "$PATCH_ROOT/var/cache/apt/archives/lock" "$PATCH_ROOT/var/lib/dpkg/lock*" 2>/dev/null || true

chroot "$PATCH_ROOT" apt-get update
chroot "$PATCH_ROOT" apt-get install -y --no-install-recommends \
  brightnessctl \
  xinput-calibrator \
  libasound2 \
  alsa-utils \
  wmctrl \
  xdotool \
  libnss3 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libcups2 \
  libdrm2 \
  libgtk-3-0 \
  libgbm1 \
  lightdm-gtk-greeter \
  i3 \
  i3status \
  dmenu \
  feh \
  ufw \
  python3-prompt-toolkit

# Install Bitwarden Desktop deb
if [ -f "$CACHE_DIR/Bitwarden-amd64.deb" ]; then
  cp "$CACHE_DIR/Bitwarden-amd64.deb" "$PATCH_ROOT/tmp/Bitwarden-amd64.deb"
  chroot "$PATCH_ROOT" dpkg -i /tmp/Bitwarden-amd64.deb || chroot "$PATCH_ROOT" apt-get install -f -y
  rm -f "$PATCH_ROOT/tmp/Bitwarden-amd64.deb"
fi

# Install Bitwarden CLI (bw)
if [ -f "$CACHE_DIR/bw" ]; then
  cp "$CACHE_DIR/bw" "$PATCH_ROOT/usr/local/bin/bw"
  chmod +x "$PATCH_ROOT/usr/local/bin/bw"
fi

# Enable Panasonic Toughbook laptop module
if ! grep -q "panasonic-laptop" "$PATCH_ROOT/etc/modules" 2>/dev/null; then
  echo "panasonic-laptop" >> "$PATCH_ROOT/etc/modules"
fi

# Clean up apt caches
chroot "$PATCH_ROOT" apt-get clean
rm -rf "$PATCH_ROOT/var/lib/apt/lists/*"

umount -l "$PATCH_ROOT/dev/pts" 2>/dev/null || true
umount -l "$PATCH_ROOT/dev" 2>/dev/null || true
umount -l "$PATCH_ROOT/sys" 2>/dev/null || true
umount -l "$PATCH_ROOT/proc" 2>/dev/null || true

echo "[*] Installing complete llama.cpp binary stack and shared libraries..."
mkdir -p "$PATCH_ROOT/opt/llama.cpp"
if [ -d "$CACHE_DIR/llama_bins" ]; then
  cp -a "$CACHE_DIR/llama_bins/"* "$PATCH_ROOT/opt/llama.cpp/"
fi
chmod +x "$PATCH_ROOT/opt/llama.cpp/llama-server" 2>/dev/null || true

# Ensure model GGUF is present in squashfs (safety net in case source ISO chain breaks)
mkdir -p "$PATCH_ROOT/opt/models"
if [ -f "$CACHE_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf" ] && [ ! -f "$PATCH_ROOT/opt/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf" ]; then
  echo "[*] Copying Qwen2.5-Coder-3B model into squashfs root..."
  cp "$CACHE_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf" "$PATCH_ROOT/opt/models/"
elif [ -f "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" ] && [ ! -f "$PATCH_ROOT/opt/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" ]; then
  echo "[*] Copying Qwen2.5-Coder-1.5B fallback model into squashfs root..."
  cp "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" "$PATCH_ROOT/opt/models/"
fi

# Configure ld.so for llama.cpp libraries
echo "/opt/llama.cpp" > "$PATCH_ROOT/etc/ld.so.conf.d/llama.conf"
chroot "$PATCH_ROOT" ldconfig 2>/dev/null || true

echo "[*] Configuring systemd service for llama-server..."
cat << 'SVCEOF' > "$PATCH_ROOT/etc/systemd/system/llama-server.service"
[Unit]
Description=Revenant OS Local Llama Inference Server
After=network.target
StartLimitBurst=0

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/opt/llama.cpp
ExecStart=/bin/bash -c 'MODEL=/opt/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf; [ -f "$MODEL" ] || MODEL=/opt/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf; exec /opt/llama.cpp/llama-server --model "$MODEL" --alias qwen2.5-coder-3b-instruct --alias qwen2.5-coder-1.5b-instruct --alias default --host 127.0.0.1 --port 8080 --ctx-size 4096 --threads 2 -np 1 -sps 0 --repeat-penalty 1.20 --repeat-last-n 128 --presence-penalty 0.1 --n-gpu-layers 0'
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

mkdir -p "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/llama-server.service "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants/llama-server.service"
ln -sf /etc/systemd/system/openviking.service "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants/openviking.service"

echo "[*] Ensuring kernel config files exist in /boot for initramfs-tools..."
mkdir -p "$PATCH_ROOT/boot"
for kimg in "$PATCH_ROOT/boot"/vmlinuz-*; do
  if [ -f "$kimg" ]; then
    kver=$(basename "$kimg" | sed 's/^vmlinuz-//')
    cat << 'CFG_EOF' > "$PATCH_ROOT/boot/config-$kver"
CONFIG_RD_GZIP=y
CONFIG_RD_BZIP2=y
CONFIG_RD_LZMA=y
CONFIG_RD_XZ=y
CONFIG_RD_LZO=y
CONFIG_RD_LZ4=y
CONFIG_RD_ZSTD=y
CFG_EOF
  fi
done
cat << 'CFG_EOF' > "$PATCH_ROOT/boot/config-6.1.0-50-amd64"
CONFIG_RD_GZIP=y
CONFIG_RD_BZIP2=y
CONFIG_RD_LZMA=y
CONFIG_RD_XZ=y
CONFIG_RD_LZO=y
CONFIG_RD_LZ4=y
CONFIG_RD_ZSTD=y
CFG_EOF

echo "[*] Purging legacy services and background agents..."
rm -f "$PATCH_ROOT/etc/systemd/system/omniroute.service"
rm -f "$PATCH_ROOT/usr/local/bin/omniroute" "$PATCH_ROOT/usr/bin/omniroute"
rm -f "$PATCH_ROOT/usr/local/bin/hermes" "$PATCH_ROOT/usr/bin/hermes"
rm -rf "$PATCH_ROOT/usr/lib/node_modules/hermes-agent" "$PATCH_ROOT/usr/lib/node_modules/omniroute"
for target_dir in "$PATCH_ROOT/root/.hermes" "$PATCH_ROOT/etc/skel/.hermes" "$PATCH_ROOT/home/user/.hermes" "$PATCH_ROOT/home/revenant/.hermes"; do
  rm -rf "$target_dir"
done

echo "[*] Configuring LightDM login screen branding & de-branding Debian..."
mkdir -p "$PATCH_ROOT/usr/share/backgrounds" "$PATCH_ROOT/usr/share/images/desktop-base" "$PATCH_ROOT/etc/lightdm/lightdm-gtk-greeter.conf.d" "$PATCH_ROOT/usr/share/icons"

# Purge any Debian greeter config overrides
rm -f "$PATCH_ROOT/etc/lightdm/lightdm-gtk-greeter.conf.d/"*debian*.conf 2>/dev/null || true
rm -f "$PATCH_ROOT/usr/share/lightdm/lightdm-gtk-greeter.conf.d/"*debian*.conf 2>/dev/null || true
rm -f "$PATCH_ROOT/etc/lightdm/lightdm-gtk-greeter.conf.d/01-revenant.conf" 2>/dev/null || true

if [ -f "$SCRIPT_DIR/revenant_bootsplash.png" ]; then
  mkdir -p "$PATCH_ROOT/usr/share/backgrounds" "$PATCH_ROOT/usr/share/images/desktop-base" "$PATCH_ROOT/boot/grub"
  cp -f --remove-destination "$SCRIPT_DIR/revenant_bootsplash.png" "$PATCH_ROOT/usr/share/backgrounds/revenant_bootsplash.png"
  cp -f --remove-destination "$SCRIPT_DIR/revenant_bootsplash.png" "$PATCH_ROOT/usr/share/images/desktop-base/desktop-background"
  cp -f --remove-destination "$SCRIPT_DIR/revenant_bootsplash.png" "$PATCH_ROOT/usr/share/images/desktop-base/login-background.svg"
  cp -f --remove-destination "$SCRIPT_DIR/revenant_bootsplash.png" "$PATCH_ROOT/boot/grub/splash.png" 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/revenant_wallpaper.jpg" ]; then
  cp -f --remove-destination "$SCRIPT_DIR/revenant_wallpaper.jpg" "$PATCH_ROOT/usr/share/backgrounds/revenant_wallpaper.jpg"
fi
if [ -f "$SCRIPT_DIR/revenant_logo.png" ]; then
  cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$PATCH_ROOT/usr/share/icons/revenant-logo.png"
  cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$PATCH_ROOT/usr/share/icons/revenant-avatar.png"

  # Completely overwrite Debian default avatars and all user account avatars with Revenant 'R' badge
  for av_dest in "$PATCH_ROOT/usr/share/images/desktop-base/avatar.png" "$PATCH_ROOT/usr/share/icons/desktop-base/avatar.png" \
                 "$PATCH_ROOT/usr/share/images/desktop-base/avatar.svg" "$PATCH_ROOT/usr/share/icons/desktop-base/avatar.svg"; do
    cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$av_dest" 2>/dev/null || true
  done

  # Overwrite default skel and root avatars
  cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$PATCH_ROOT/etc/skel/.face" 2>/dev/null || true
  cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$PATCH_ROOT/etc/skel/.face.icon" 2>/dev/null || true
  cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$PATCH_ROOT/root/.face" 2>/dev/null || true
  cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$PATCH_ROOT/root/.face.icon" 2>/dev/null || true

  # Overwrite all existing user avatars in /home/*
  for uhome in "$PATCH_ROOT/home"/*; do
    if [ -d "$uhome" ]; then
      cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$uhome/.face" 2>/dev/null || true
      cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$uhome/.face.icon" 2>/dev/null || true
    fi
  done

  # Overwrite AccountsService avatar cache
  if [ -d "$PATCH_ROOT/var/lib/AccountsService/icons" ]; then
    for icon_file in "$PATCH_ROOT/var/lib/AccountsService/icons"/*; do
      if [ -f "$icon_file" ]; then
        cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$icon_file" 2>/dev/null || true
      fi
    done
  fi
fi

# Neutralize vendor Debian logo icons with the Revenant badge
for deb_icon in "$PATCH_ROOT/usr/share/icons/desktop-base/debian.svg" \
               "$PATCH_ROOT/usr/share/icons/desktop-base/debian-logo.svg" \
               "$PATCH_ROOT/usr/share/icons/desktop-base/"*debian*.svg \
               "$PATCH_ROOT/usr/share/icons/desktop-base/"*debian*.png \
               "$PATCH_ROOT/usr/share/icons/hicolor/scalable/apps/debian-logo.svg" \
               "$PATCH_ROOT/usr/share/icons/hicolor/"*/apps/debian*.png \
               "$PATCH_ROOT/usr/share/icons/hicolor/"*/apps/debian*.svg; do
  if [ -f "$deb_icon" ] && [ -f "$SCRIPT_DIR/revenant_logo.png" ]; then
    cp -f --remove-destination "$SCRIPT_DIR/revenant_logo.png" "$deb_icon" 2>/dev/null || true
  fi
done

cat << 'GREETER_CONF_EOF' > "$PATCH_ROOT/etc/lightdm/lightdm-gtk-greeter.conf.d/99_revenant.conf"
[greeter]
background = /usr/share/backgrounds/revenant_bootsplash.png
theme-name = Adwaita-dark
icon-theme-name = Papirus-Dark
cursor-theme-name = Adwaita
font-name = Sans 10
xft-antialias = true
xft-dpi = 96
xft-hintstyle = slight
xft-rgba = rgb
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %a, %d %b  %H:%M
default-user-image = /usr/share/icons/revenant-avatar.png
logo = /usr/share/icons/revenant-logo.png
hide-user-image = false
GREETER_CONF_EOF

cat << 'GREETER_MAIN_EOF' > "$PATCH_ROOT/etc/lightdm/lightdm-gtk-greeter.conf"
[greeter]
background = /usr/share/backgrounds/revenant_bootsplash.png
theme-name = Adwaita-dark
icon-theme-name = Papirus-Dark
cursor-theme-name = Adwaita
font-name = Sans 10
xft-antialias = true
xft-dpi = 96
xft-hintstyle = slight
xft-rgba = rgb
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %a, %d %b  %H:%M
default-user-image = /usr/share/icons/revenant-avatar.png
logo = /usr/share/icons/revenant-logo.png
hide-user-image = false
GREETER_MAIN_EOF

echo "[*] Setting up Whisper STT and deploying voice-enabled Revenant Custom Agent..."
mkdir -p "$PATCH_ROOT/opt/whisper/models"

cat << 'AGENT_EOF' > "$PATCH_ROOT/usr/local/bin/revenant-agent"
#!/usr/bin/env python3
# ==============================================================================
# Revenant OS - Unified Autonomous Field Agent Core (CPU-Optimized for Toughbook)
# Personas: General, Mechanic (Automotive/CAN), Electronics (Circuits), SysAdmin
# Memory: OpenViking integration (/remember, /recall, auto-context)
# Engines: Local (Qwen 2.5 Coder 3B) & OmniRoute/Cloud API (/cloud, /local)
# Hardware: Toughbook CF-52 Mic Boost, Whisper STT, Piper TTS & Telemetry
# ==============================================================================
import sys, os, json, re, urllib.request, urllib.error, subprocess, glob, time, signal, atexit, shutil, select

try:
    import termios, tty
    TERMIOS_AVAILABLE = True
except ImportError:
    TERMIOS_AVAILABLE = False

try:
    import readline
except ImportError:
    readline = None

try:
    from prompt_toolkit import PromptSession
    from prompt_toolkit.auto_suggest import AutoSuggestFromHistory
    from prompt_toolkit.completion import WordCompleter
    from prompt_toolkit.history import FileHistory
    from prompt_toolkit.styles import Style
    from prompt_toolkit.formatted_text import HTML
    PROMPT_TOOLKIT_AVAILABLE = True
except ImportError:
    PROMPT_TOOLKIT_AVAILABLE = False

CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
MAGENTA = "\033[95m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"

PERSONAS = {
    "general": {
        "name": "General Field Assistant",
        "color": CYAN,
        "prompt": """You are the Revenant OS Autonomous Field Agent on a Panasonic Toughbook.
You are concise, highly practical, and an expert in Linux systems, bash automation, and computing.
You can inspect the system and run actions using:
- [EXEC: bash_command] to execute terminal commands (e.g. [EXEC: df -h], [EXEC: ip a])
- [READ: filepath] to view file contents
- [WRITE: filepath | content] to create or update files
Keep explanations brief and action-oriented."""
    },
    "mechanic": {
        "name": "Motor Mechanic Specialist",
        "color": YELLOW,
        "prompt": """You are the Revenant OS Motor Mechanic Field Diagnostic Agent on a Panasonic Toughbook.
You specialize in automotive diagnostics, OBD-II DTC troubleshooting (P0xxx, P1xxx, Uxxxx, Bxxxx, Cxxxx), CAN bus analysis (candump, cansend, can-utils), diesel/petrol engine mechanical repair, electrical wiring traces, sensor testing (MAF, MAP, O2, TPS, CKP, CMP), starter/alternator/battery load tests, and component replacement sequences.
You can run diagnostic actions using:
- [EXEC: bash_command] to run diagnostic commands (e.g. candump can0, dmesg, serial queries)
- [READ: filepath] to view logs or DTC manuals
- [WRITE: filepath | content] to record vehicle inspection notes
Provide step-by-step, highly practical diagnostic procedures."""
    },
    "electronics": {
        "name": "Electronics Specialist",
        "color": MAGENTA,
        "prompt": """You are the Revenant OS Electronics Diagnostic Specialist on a Panasonic Toughbook.
You specialize in circuit troubleshooting, board-level repair, semiconductor testing (MOSFETs, diodes, transistors, voltage regulators), multimeter/oscilloscope test points, schematic analysis, soldering/rework guidance, and microcontroller firmware (Arduino, ESP32, STM32, PIC).
You can inspect and flash hardware using:
- [EXEC: bash_command] to run commands (e.g. lsusb, dmesg, minicom, avrdude, esptool)
- [READ: filepath] to inspect pinouts or datasheets
- [WRITE: filepath | content] to write firmware or notes
Provide clear, safe, component-level diagnostic steps and pinout details."""
    },
    "sysadmin": {
        "name": "Linux Systems Administrator",
        "color": GREEN,
        "prompt": """You are the Revenant OS Field Linux Systems Administrator on a Panasonic Toughbook.
You specialize in Linux system recovery, network diagnostics (ip, ss, tcpdump, ping, ethtool), kernel module troubleshooting, serial interface configuration (/dev/ttyUSB*, /dev/ttyS*), disk and partition repair (fsck, parted, smartctl, dd), systemd service management, and rugged field automation.
You can perform administrative recovery using:
- [EXEC: bash_command] to execute recovery actions
- [READ: filepath] to read configs and system logs
- [WRITE: filepath | content] to patch system configurations
Provide exact, reliable terminal commands and concise technical explanations."""
    }
}

CONFIG_DIR = os.path.expanduser("~/.revenant")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")
CLOUD_CONF_PATH = os.path.join(CONFIG_DIR, "cloud.conf")
MEMORY_FALLBACK_PATH = os.path.join(CONFIG_DIR, "agent_memory.json")
HISTORY_PATH = os.path.join(CONFIG_DIR, "agent_history")
PID_FILE = "/tmp/revenant_agent.pid"

def load_config():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    cfg = {
        "voice_enabled": False,
        "default_mode": "general",
        "default_engine": "local"
    }
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, 'r') as f:
                cfg.update(json.load(f))
        except Exception:
            pass
    return cfg

def save_config(cfg):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    try:
        with open(CONFIG_PATH, 'w') as f:
            json.dump(cfg, f, indent=2)
    except Exception:
        pass

app_cfg = load_config()
VOICE_ENABLED = app_cfg.get("voice_enabled", False)
mic_requested = False
current_mode = app_cfg.get("default_mode", "general")
current_engine = app_cfg.get("default_engine", "local")
current_speech_proc = None

def cleanup_pid():
    try:
        if os.path.exists(PID_FILE):
            with open(PID_FILE, 'r') as f:
                if f.read().strip() == str(os.getpid()):
                    os.remove(PID_FILE)
    except Exception:
        pass

atexit.register(cleanup_pid)
try:
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))
except Exception:
    pass

class VoiceTrigger(Exception):
    pass

class StreamCancelled(Exception):
    pass

def handle_voice_signal(signum, frame):
    global mic_requested
    mic_requested = True
    raise VoiceTrigger()

try:
    signal.signal(signal.SIGUSR1, handle_voice_signal)
    signal.siginterrupt(signal.SIGUSR1, True)
except Exception:
    pass

def stop_speech():
    global current_speech_proc
    if current_speech_proc:
        try:
            current_speech_proc.terminate()
            current_speech_proc.kill()
        except Exception:
            pass
        current_speech_proc = None
    try:
        subprocess.run("pkill -9 aplay; pkill -9 piper", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def speak_text(text):
    global current_speech_proc
    if not VOICE_ENABLED:
        return
    clean = re.sub(r'\[.*?\]', '', text)
    clean = re.sub(r'[*`#_"\']', '', clean).strip()
    if clean:
        stop_speech()
        cmd = f"echo '{clean}' | /opt/piper/piper -m /opt/piper/models/en_US-lessac-medium.onnx --output_raw 2>/dev/null | aplay -r 22050 -f S16_LE -t raw - 2>/dev/null"
        try:
            current_speech_proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

class RawTerminalInput:
    """Non-blocking cbreak terminal input to detect Esc and Ctrl+C during streaming."""
    def __enter__(self):
        self.fd = None
        self.old_settings = None
        if TERMIOS_AVAILABLE and sys.stdin.isatty():
            try:
                self.fd = sys.stdin.fileno()
                self.old_settings = termios.tcgetattr(self.fd)
                tty.setcbreak(self.fd)
            except Exception:
                pass
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.fd is not None and self.old_settings is not None:
            try:
                termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old_settings)
            except Exception:
                pass

    def check_cancel(self):
        if not TERMIOS_AVAILABLE or not sys.stdin.isatty():
            return False
        try:
            r, _, _ = select.select([sys.stdin], [], [], 0)
            if r:
                data = os.read(sys.stdin.fileno(), 1024)
                if b'\x1b' in data or b'\x03' in data:
                    return True
        except Exception:
            pass
        return False

def configure_microphone():
    controls = [
        "amixer -q set Capture 95% unmute",
        "amixer -q set 'Capture',0 95% unmute",
        "amixer -q set 'Internal Mic' 95% unmute",
        "amixer -q set 'Mic' 95% unmute",
        "amixer -q set 'Front Mic' 95% unmute",
        "amixer -q set 'Mic Boost' 2 unmute",
        "amixer -q set 'Capture Boost' 2 unmute",
        "amixer -q set 'Input Source' 'Internal Mic' || amixer -q set 'Input Source' 'Mic'",
        "amixer -q sset 'Capture' cap",
        "amixer -q sset 'Internal Mic' cap"
    ]
    for cmd in controls:
        subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def record_voice(duration=5, output_wav="/tmp/revenant_voice.wav"):
    configure_microphone()
    try:
        if os.path.exists(output_wav):
            try:
                os.remove(output_wav)
            except Exception:
                pass
        print(f"\n{YELLOW}🎙️  [Listening... Speak into microphone ({duration}s)...]{RESET}")
        cmd = f"arecord -q -d {duration} -r 16000 -c 1 -f S16_LE '{output_wav}'"
        res = subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if res.returncode != 0 or not os.path.exists(output_wav) or os.path.getsize(output_wav) < 1000:
            cmd = f"arecord -q -D plughw:0,0 -d {duration} -r 16000 -c 1 -f S16_LE '{output_wav}'"
            res = subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return os.path.exists(output_wav) and os.path.getsize(output_wav) > 1000
    except Exception as e:
        print(f"{RED}[!] Audio record error: {e}{RESET}")
        return False

def transcribe_voice(wav_path="/tmp/revenant_voice.wav"):
    if not os.path.exists(wav_path):
        return ""
    whisper_bin = "/opt/whisper/whisper-cli"
    model_path = "/opt/whisper/models/ggml-tiny.en.bin"
    print(f"{CYAN}⚡ [Transcribing voice with local Whisper STT...]{RESET}")
    if os.path.exists(whisper_bin) and os.path.exists(model_path):
        try:
            proc = subprocess.run(
                [whisper_bin, "-m", model_path, "-f", wav_path, "--no-timestamps", "-nt"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
            )
            raw = proc.stdout.strip()
            return re.sub(r'\[.*?\]', '', raw).strip()
        except Exception:
            pass
    try:
        from pywhispercpp.model import Model
        m = Model('tiny.en', models_dir='/opt/whisper/models')
        segs = m.transcribe(wav_path)
        return " ".join([s.text for s in segs]).strip()
    except Exception:
        pass
    return ""

def handle_mic_input():
    if record_voice(duration=5):
        transcript = transcribe_voice()
        if transcript:
            print(f"{GREEN}✓ Speech recognized:{RESET} {BOLD}\"{transcript}\"{RESET}")
            print(f"{DIM}(Review or edit prompt below, then hit Enter to execute){RESET}\n")
            set_input_buffer(transcript)
            return transcript
        else:
            print(f"{YELLOW}[No speech detected or transcription empty]{RESET}\n")
    else:
        print(f"{RED}[!] Could not capture audio from microphone.{RESET}\n")
    return ""

def get_system_telemetry():
    telemetry = []
    bats = glob.glob('/sys/class/power_supply/BAT*/capacity')
    if bats:
        try:
            with open(bats[0]) as f:
                telemetry.append(f"Battery: {f.read().strip()}%")
        except Exception:
            pass
    temps = glob.glob('/sys/class/thermal/thermal_zone*/temp')
    if temps:
        try:
            with open(temps[0]) as f:
                telemetry.append(f"Temp: {int(f.read().strip())/1000.0:.1f}°C")
        except Exception:
            pass
    try:
        out = subprocess.check_output("free -m | awk '/Mem:/ {print $3\"/\"$2\"MB\"}'", shell=True).decode().strip()
        telemetry.append(f"RAM: {out}")
    except Exception:
        pass
    return " | ".join(telemetry)

def load_cloud_config():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    conf = {
        "base_url": os.getenv("OMNIROUTE_URL", "http://localhost:20128/v1"),
        "api_key": os.getenv("OPENROUTER_API_KEY", "sk-omniroute"),
        "model": "deepseek/deepseek-chat"
    }
    if os.path.exists(CLOUD_CONF_PATH):
        try:
            with open(CLOUD_CONF_PATH, 'r') as f:
                conf.update(json.load(f))
        except Exception:
            pass
    return conf

def save_cloud_config(conf):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    try:
        with open(CLOUD_CONF_PATH, 'w') as f:
            json.dump(conf, f, indent=2)
    except Exception:
        pass

def query_openviking(query, timeout=2.0):
    if not query or len(query.strip()) < 4:
        return ""
    ov_bin = shutil.which("ov") or "/usr/local/bin/ov"
    if os.path.exists(ov_bin):
        try:
            proc = subprocess.run(
                [ov_bin, "find", query],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout
            )
            if proc.returncode == 0 and proc.stdout.strip():
                clean = proc.stdout.strip()
                return clean[:600] + ("..." if len(clean) > 600 else "")
        except Exception:
            pass
    if os.path.exists(MEMORY_FALLBACK_PATH):
        try:
            with open(MEMORY_FALLBACK_PATH, 'r') as f:
                memories = json.load(f)
            words = set(re.findall(r'\w+', query.lower()))
            matches = [m for m in memories if words & set(re.findall(r'\w+', m.lower()))]
            if matches:
                return "\n".join(matches[-2:])
        except Exception:
            pass
    return ""

def remember_fact(fact):
    fact = fact.strip()
    if not fact:
        return False
    ov_bin = shutil.which("ov") or "/usr/local/bin/ov"
    if os.path.exists(ov_bin):
        try:
            subprocess.run([ov_bin, "add", fact], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2.5)
        except Exception:
            pass
    os.makedirs(CONFIG_DIR, exist_ok=True)
    memories = []
    if os.path.exists(MEMORY_FALLBACK_PATH):
        try:
            with open(MEMORY_FALLBACK_PATH, 'r') as f:
                memories = json.load(f)
        except Exception:
            memories = []
    if fact not in memories:
        memories.append(fact)
        if len(memories) > 200:
            memories = memories[-200:]
        try:
            with open(MEMORY_FALLBACK_PATH, 'w') as f:
                json.dump(memories, f, indent=2)
            return True
        except Exception:
            pass
    return True

def execute_tool(action_type, payload):
    if action_type == "EXEC":
        cmd = payload.strip()
        print(f"\n{YELLOW}{BOLD}▶ Proposed Action:{RESET} {CYAN}{cmd}{RESET}")
        choice = input(f"{YELLOW}Execute? [Y/n/edit]: {RESET}").strip().lower()
        if choice in ('', 'y', 'yes'):
            try:
                proc = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
                output = proc.stdout.strip()
                print(f"{DIM}{output}{RESET}\n")
                return f"Exit code {proc.returncode}\nOutput:\n{output}"
            except subprocess.TimeoutExpired:
                print(f"{RED}[Command timed out after 60s]{RESET}")
                return "Command timed out after 60 seconds."
            except Exception as e:
                return f"Error executing command: {e}"
        elif choice == 'edit':
            new_cmd = input(f"{YELLOW}Edit command: {RESET}").strip()
            if new_cmd:
                return execute_tool("EXEC", new_cmd)
            return "Command cancelled."
        else:
            print(f"{RED}Command cancelled by user.{RESET}")
            return "Command rejected by user."

    elif action_type == "READ":
        path = payload.strip()
        if not os.path.exists(path):
            return f"Error: File {path} does not exist."
        try:
            with open(path, 'r', errors='ignore') as f:
                content = f.read(4000)
            print(f"{GREEN}[Read {path} ({len(content)} chars)]{RESET}")
            return f"Contents of {path}:\n{content}"
        except Exception as e:
            return f"Error reading {path}: {e}"

    elif action_type == "WRITE":
        parts = payload.split('|', 1)
        if len(parts) == 2:
            path, content = parts[0].strip(), parts[1].strip()
            try:
                with open(path, 'w') as f:
                    f.write(content)
                print(f"{GREEN}[Wrote to {path}]{RESET}")
                return f"Successfully written to {path}"
            except Exception as e:
                return f"Error writing to {path}: {e}"
        return "Error: Invalid WRITE syntax. Use [WRITE: filepath | content]"

    return "Unknown tool action."

def call_model(messages, max_tokens=384):
    global current_engine
    with RawTerminalInput() as term_input:
        if current_engine == "cloud":
            conf = load_cloud_config()
            url = conf.get("base_url", "http://localhost:20128/v1").rstrip('/') + "/chat/completions"
            api_key = conf.get("api_key", "sk-omniroute")
            model = conf.get("model", "deepseek/deepseek-chat")

            payload = json.dumps({
                "model": model,
                "messages": messages,
                "temperature": 0.5,
                "max_tokens": max_tokens,
                "stream": True
            }).encode('utf-8')

            req = urllib.request.Request(
                url,
                data=payload,
                headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
            )

            try:
                collected = []
                with urllib.request.urlopen(req, timeout=30) as resp:
                    for line in resp:
                        if term_input.check_cancel():
                            stop_speech()
                            raise StreamCancelled()
                        line = line.decode('utf-8').strip()
                        if not line or not line.startswith("data: "):
                            continue
                        data_str = line[6:]
                        if data_str == "[DONE]":
                            break
                        try:
                            chunk = json.loads(data_str)
                            delta = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                            if delta:
                                sys.stdout.write(delta)
                                sys.stdout.flush()
                                collected.append(delta)
                        except json.JSONDecodeError:
                            pass
                print()
                return "".join(collected)
            except StreamCancelled:
                raise
            except Exception as e:
                print(f"\n{YELLOW}[!] OmniRoute/Cloud endpoint error ({e}). Falling back to local neural engine...{RESET}")

        # Fallback / Local Model (llama-server)
        payload = json.dumps({
            "model": "default",
            "messages": messages,
            "temperature": 0.5,
            "max_tokens": max_tokens,
            "stream": True
        }).encode('utf-8')

        req = urllib.request.Request(
            "http://127.0.0.1:8080/v1/chat/completions",
            data=payload,
            headers={"Content-Type": "application/json"}
        )

        collected = []
        with urllib.request.urlopen(req, timeout=60) as resp:
            for line in resp:
                if term_input.check_cancel():
                    stop_speech()
                    raise StreamCancelled()
                line = line.decode('utf-8').strip()
                if not line or not line.startswith("data: "):
                    continue
                data_str = line[6:]
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                    delta = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    if delta:
                        sys.stdout.write(delta)
                        sys.stdout.flush()
                        collected.append(delta)
                except json.JSONDecodeError:
                    pass
        print()
        return "".join(collected)

def print_banner():
    p = PERSONAS.get(current_mode, PERSONAS["general"])
    col = p["color"]
    os.system('clear')
    print(f"{col}{BOLD}=========================================================={RESET}")
    print(f"{col}{BOLD}    REVENANT OS - AUTONOMOUS FIELD AGENT ({p['name'].upper()})   {RESET}")
    print(f"{col}{BOLD}=========================================================={RESET}")
    telem = get_system_telemetry()
    if telem:
        print(f"{DIM}{telem}{RESET}")
    eng_str = f"{GREEN}Local 3B (Offline){RESET}" if current_engine == "local" else f"{CYAN}OmniRoute / Cloud{RESET}"
    voice_str = f"{GREEN}Voice: ON 🔊{RESET}" if VOICE_ENABLED else f"{YELLOW}Voice: OFF 🔇{RESET}"
    predict_str = f"{GREEN}Fish Autosuggest Active{RESET}" if PROMPT_TOOLKIT_AVAILABLE else f"{DIM}Readline Mode{RESET}"
    print(f"{DIM}Engine: [{eng_str}{DIM}] | Memory: [{GREEN}OpenViking Active{RESET}{DIM}] | [{voice_str}{DIM}] | Mode: [{col}{p['name']}{RESET}{DIM}]{RESET}")
    print(f"{DIM}Predictive: [{predict_str}{DIM}] (Press → to accept suggestions | Press <Esc> to cancel thinking){RESET}")
    print(f"{CYAN}OmniRoute Web UI: http://localhost:20128 (Open in browser to configure free APIs){RESET}")
    print(f"{DIM}Commands: /mechanic | /electronics | /sysadmin | /voice on/off | /cloud | /local | /remember | /recall{RESET}")
    print(f"{CYAN}Hotkeys:  Press <Super>+M anytime to speak directly into this window.{RESET}\n")

def run_agent_loop(initial_prompt=None, initial_mic=False):
    global VOICE_ENABLED, mic_requested, current_mode, current_engine, app_cfg
    print_banner()

    history = [
        {"role": "system", "content": PERSONAS[current_mode]["prompt"]}
    ]

    slash_commands = [
        '/mechanic', '/electronics', '/sysadmin', '/general',
        '/cloud', '/cloud config', '/local',
        '/remember', '/recall',
        '/voice', '/voice on', '/voice off', '/mute', '/unmute',
        '/mic', '/talk', '/listen', '/clear', '/sysinfo', '/hw', '/help', 'exit', 'quit'
    ]

    session = None
    if PROMPT_TOOLKIT_AVAILABLE:
        try:
            session = PromptSession(
                history=FileHistory(HISTORY_PATH),
                auto_suggest=AutoSuggestFromHistory(),
                completer=WordCompleter(slash_commands, ignore_case=True, sentence=True),
                style=Style.from_dict({
                    'auto-suggest': '#777777 italic',
                    'prompt': '#00ff88 bold',
                })
            )
        except Exception:
            session = None

    pending_user_input = initial_prompt
    if initial_mic:
        handle_mic_input()

    while True:
        if mic_requested:
            mic_requested = False
            handle_mic_input()

        p = PERSONAS.get(current_mode, PERSONAS["general"])
        col = p["color"]

        if pending_user_input:
            user_input = pending_user_input
            pending_user_input = None
        else:
            try:
                if session is not None:
                    prompt_html = HTML(f"<b><ansigreen>{current_mode}</ansigreen></b> ❯ ")
                    if current_mode == "mechanic":
                        prompt_html = HTML(f"<b><ansiyellow>{current_mode}</ansiyellow></b> ❯ ")
                    elif current_mode == "electronics":
                        prompt_html = HTML(f"<b><ansimagenta>{current_mode}</ansimagenta></b> ❯ ")
                    elif current_mode == "general":
                        prompt_html = HTML(f"<b><ansicyan>{current_mode}</ansicyan></b> ❯ ")
                    user_input = session.prompt(prompt_html).strip()
                else:
                    user_input = input(f"{col}{BOLD}{current_mode} ❯ {RESET}").strip()
            except (VoiceTrigger, InterruptedError):
                mic_requested = False
                handle_mic_input()
                continue
            except (KeyboardInterrupt, EOFError):
                if mic_requested:
                    mic_requested = False
                    handle_mic_input()
                    continue
                print(f"\n{YELLOW}Exiting Revenant Agent. Goodbye!{RESET}")
                break

        if not user_input:
            continue

        cmd_lower = user_input.lower()
        if cmd_lower in ('exit', 'quit', ':q'):
            print(f"\n{YELLOW}Exiting Revenant Agent. Goodbye!{RESET}")
            break

        # Persona / Mode switching
        if cmd_lower in ('/mechanic', '/mech'):
            current_mode = "mechanic"
            history[0] = {"role": "system", "content": PERSONAS["mechanic"]["prompt"]}
            print(f"\n{YELLOW}[✓] Switched to Motor Mechanic Field Specialist mode.{RESET}")
            print(f"{DIM}Automotive diagnostics, DTC OBD-II, CAN bus & engine repair loaded.{RESET}\n")
            continue
        elif cmd_lower in ('/electronics', '/elec'):
            current_mode = "electronics"
            history[0] = {"role": "system", "content": PERSONAS["electronics"]["prompt"]}
            print(f"\n{MAGENTA}[✓] Switched to Electronics Specialist mode.{RESET}")
            print(f"{DIM}Circuit board diagnostics, multimeter test points & microcontrollers loaded.{RESET}\n")
            continue
        elif cmd_lower in ('/sysadmin', '/sys'):
            current_mode = "sysadmin"
            history[0] = {"role": "system", "content": PERSONAS["sysadmin"]["prompt"]}
            print(f"\n{GREEN}[✓] Switched to Field Linux Systems Administrator mode.{RESET}")
            print(f"{DIM}System recovery, network analysis, disk repair & serial comms loaded.{RESET}\n")
            continue
        elif cmd_lower in ('/general', '/coder', '/ai'):
            current_mode = "general"
            history[0] = {"role": "system", "content": PERSONAS["general"]["prompt"]}
            print(f"\n{CYAN}[✓] Switched to General Field Assistant mode.{RESET}\n")
            continue
        elif cmd_lower.startswith('/mode '):
            target = cmd_lower.split('/mode ', 1)[1].strip()
            if target in PERSONAS:
                current_mode = target
                history[0] = {"role": "system", "content": PERSONAS[target]["prompt"]}
                print(f"\n{PERSONAS[target]['color']}[✓] Switched to {PERSONAS[target]['name']} mode.{RESET}\n")
            else:
                print(f"{RED}[!] Unknown mode: {target}. Available: general, mechanic, electronics, sysadmin{RESET}\n")
            continue

        # Engine switching: OmniRoute / Cloud vs Local
        elif cmd_lower in ('/cloud', '/omniroute'):
            current_engine = "cloud"
            conf = load_cloud_config()
            print(f"\n{CYAN}[✓] Switched to OmniRoute / Cloud Engine.{RESET}")
            print(f"{DIM}Endpoint: {conf['base_url']} | Model: {conf['model']}{RESET}")
            print(f"{CYAN}OmniRoute Web UI: http://localhost:20128 (Configure free APIs in browser){RESET}")
            print(f"{DIM}(Type /local to return to offline CPU or /cloud config to edit settings){RESET}\n")
            continue
        elif cmd_lower.startswith('/cloud config') or cmd_lower.startswith('/cloud setup'):
            conf = load_cloud_config()
            print(f"\n{CYAN}{BOLD}--- OmniRoute / Cloud Settings ---{RESET}")
            new_url = input(f"Base URL [{conf['base_url']}]: ").strip()
            if new_url:
                conf['base_url'] = new_url
            new_key = input(f"API Key (or Enter for default): ").strip()
            if new_key:
                conf['api_key'] = new_key
            new_model = input(f"Model [{conf['model']}]: ").strip()
            if new_model:
                conf['model'] = new_model
            save_cloud_config(conf)
            print(f"{GREEN}[✓] OmniRoute / Cloud configuration updated and saved.{RESET}\n")
            continue
        elif cmd_lower == '/local':
            current_engine = "local"
            print(f"\n{GREEN}[✓] Switched to Offline Local Neural Engine (Qwen 2.5 Coder 3B).{RESET}\n")
            continue

        # Memory commands
        elif cmd_lower.startswith('/remember '):
            fact = user_input[10:].strip()
            if remember_fact(fact):
                print(f"{GREEN}[✓] Saved to OpenViking memory:{RESET} \"{fact}\"\n")
            else:
                print(f"{RED}[!] Could not save memory.{RESET}\n")
            continue
        elif cmd_lower.startswith('/recall '):
            term = user_input[8:].strip()
            recalled = query_openviking(term)
            if recalled:
                print(f"\n{GREEN}{BOLD}Recalled Memory for '{term}':{RESET}\n{recalled}\n")
            else:
                print(f"\n{YELLOW}[No memories found matching '{term}']{RESET}\n")
            continue

        # Voice talkback toggling
        elif cmd_lower in ('/voice on', '/unmute'):
            VOICE_ENABLED = True
            app_cfg['voice_enabled'] = True
            save_config(app_cfg)
            print(f"\n{GREEN}[✓] Voice talkback is now ENABLED 🔊 (Saved to preferences).{RESET}\n")
            speak_text("Voice talkback enabled.")
            continue
        elif cmd_lower in ('/voice off', '/mute'):
            VOICE_ENABLED = False
            stop_speech()
            app_cfg['voice_enabled'] = False
            save_config(app_cfg)
            print(f"\n{YELLOW}[✓] Voice talkback is now MUTED 🔇 (Saved to preferences).{RESET}\n")
            continue
        elif cmd_lower == '/voice':
            VOICE_ENABLED = not VOICE_ENABLED
            app_cfg['voice_enabled'] = VOICE_ENABLED
            save_config(app_cfg)
            if not VOICE_ENABLED:
                stop_speech()
            state = f"{GREEN}ENABLED 🔊{RESET}" if VOICE_ENABLED else f"{YELLOW}MUTED 🔇{RESET}"
            print(f"\n{CYAN}[*] Voice talkback is now {state}. (Saved to preferences){RESET}\n")
            if VOICE_ENABLED:
                speak_text("Voice talkback enabled.")
            continue

        # Utility commands
        elif cmd_lower in ('/mic', '/talk', '/listen'):
            handle_mic_input()
            continue
        elif cmd_lower == '/clear':
            history = [{"role": "system", "content": PERSONAS[current_mode]["prompt"]}]
            print(f"{GREEN}[✓] Conversation context reset.{RESET}\n")
            continue
        elif cmd_lower in ('/sysinfo', '/hw'):
            print(f"\n{CYAN}{BOLD}Toughbook Hardware Diagnostics:{RESET}")
            subprocess.run("uname -a; uptime; free -h; df -h /; sensors 2>/dev/null || true", shell=True)
            print()
            continue
        elif cmd_lower in ('/help', '/?'):
            print(f"\n{CYAN}{BOLD}Revenant Field Agent Commands:{RESET}")
            print(f"  {BOLD}/mechanic{RESET}        Switch to Automotive OBD-II DTC & CAN Bus mode")
            print(f"  {BOLD}/electronics{RESET}     Switch to Circuit Board, Multimeter & Microcontroller mode")
            print(f"  {BOLD}/sysadmin{RESET}        Switch to Linux Recovery, Network & Serial Comms mode")
            print(f"  {BOLD}/general{RESET}         Switch to General Computing & Scripting mode")
            print(f"  {BOLD}/voice [on/off]{RESET}   Toggle or set Piper voice talkback (persisted)")
            print(f"  {BOLD}/cloud{RESET}           Toggle OmniRoute / Cloud API (free APIs or OpenRouter)")
            print(f"  {BOLD}/local{RESET}           Toggle 100% Offline Local 3B Model")
            print(f"  {BOLD}/remember <text>{RESET}  Save knowledge/facts into OpenViking memory")
            print(f"  {BOLD}/recall <query>{RESET}   Search OpenViking memory database")
            print(f"  {BOLD}/mic{RESET}             Record 5s query from Toughbook microphone")
            print(f"  {BOLD}/clear{RESET}           Clear conversation context")
            print(f"  {BOLD}<Esc> / Ctrl+C{RESET}   Instantly cancel thinking or speech")
            print(f"  {BOLD}exit{RESET}             Exit agent\n")
            continue

        # Query OpenViking for relevant memory context
        mem_context = query_openviking(user_input)
        if mem_context:
            augmented = f"{user_input}\n\n[OpenViking Relevant Memory Context:\n{mem_context}]"
        else:
            augmented = user_input

        history.append({"role": "user", "content": augmented})
        if len(history) > 12:
            history = [history[0]] + history[-10:]

        eng_label = "Local 3B" if current_engine == "local" else "OmniRoute/Cloud"
        print(f"\n{CYAN}[Revenant Agent Thinking ({eng_label})... (Press <Esc> to cancel)]{RESET}")
        try:
            response = call_model(history)
            if not response:
                continue
            history.append({"role": "assistant", "content": response})
            speak_text(response)

            tool_matches = re.findall(r'\[(EXEC|READ|WRITE):\s*(.*?)\]', response, re.DOTALL)
            for action_type, payload in tool_matches:
                result = execute_tool(action_type, payload)
                history.append({"role": "user", "content": f"Tool execution result:\n{result}"})
                print(f"\n{CYAN}[Revenant Agent Analyzing Result...]{RESET}")
                followup = call_model(history, max_tokens=256)
                if followup:
                    history.append({"role": "assistant", "content": followup})
                    speak_text(followup)

            print()

        except (StreamCancelled, KeyboardInterrupt):
            stop_speech()
            print(f"\n{YELLOW}[!] Request cancelled by user (<Esc> / Ctrl+C).{RESET}\n")
            continue
        except urllib.error.URLError as e:
            print(f"\n{RED}[!] Cannot connect to inference engine: {e}{RESET}")
            print(f"{YELLOW}Ensure llama-server or OmniRoute is active: sudo systemctl restart llama-server{RESET}\n")
        except Exception as e:
            print(f"\n{RED}[!] Agent Error: {e}{RESET}\n")

if __name__ == '__main__':
    initial = None
    start_mic = False
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ('--mic', '-mic', '--voice'):
            VOICE_ENABLED = True
            start_mic = True
        elif arg in ('--mode', '-m') and i + 1 < len(args):
            i += 1
            if args[i] in PERSONAS:
                current_mode = args[i]
        elif arg in ('--cloud', '-c'):
            current_engine = "cloud"
        elif arg in ('--local', '-l'):
            current_engine = "local"
        else:
            initial = " ".join(args[i:])
            break
        i += 1

    run_agent_loop(initial_prompt=initial, initial_mic=start_mic)
AGENT_EOF
chmod +x "$PATCH_ROOT/usr/local/bin/revenant-agent"

# Pre-seed OpenInterpreter config
for target_dir in "$PATCH_ROOT/etc/skel/.config/open-interpreter" "$PATCH_ROOT/home/user/.config/open-interpreter" "$PATCH_ROOT/home/revenant/.config/open-interpreter"; do
  mkdir -p "$target_dir"
  cat << 'INTERP_CFG' > "$target_dir/config.yaml"
model: "qwen2.5-coder-1.5b-instruct"
api_base: "http://127.0.0.1:8080/v1"
api_key: "sk-local-revenant"
context_window: 2048
max_tokens: 512
offline: true
INTERP_CFG
done

echo "[*] Installing Node.js v22 (v22.23.2) standalone runtime..."
NODE_TAR="$CACHE_DIR/node-v22.23.2-linux-x64.tar.xz"
if [ ! -f "$NODE_TAR" ] && [ -f "$SCRIPT_DIR/node-v22.23.2-linux-x64.tar.xz" ]; then
  NODE_TAR="$SCRIPT_DIR/node-v22.23.2-linux-x64.tar.xz"
elif [ ! -f "$NODE_TAR" ]; then
  mkdir -p "$CACHE_DIR"
  echo "[*] Downloading Node.js v22.23.2 standalone runtime..."
  wget -q --show-progress -c "https://nodejs.org/dist/v22.23.2/node-v22.23.2-linux-x64.tar.xz" -O "$CACHE_DIR/node-v22.23.2-linux-x64.tar.xz" || true
fi

if [ -f "$NODE_TAR" ]; then
  mkdir -p "$PATCH_ROOT/opt/node"
  tar -xJf "$NODE_TAR" --strip-components=1 -C "$PATCH_ROOT/opt/node" 2>/dev/null || true
  ln -sf /opt/node/bin/node "$PATCH_ROOT/usr/local/bin/node"
  ln -sf /opt/node/bin/npm "$PATCH_ROOT/usr/local/bin/npm"
  ln -sf /opt/node/bin/npx "$PATCH_ROOT/usr/local/bin/npx"
fi

# Purge any legacy OpenCode and Pi Agent binaries, wrappers, and configurations
rm -f "$PATCH_ROOT/usr/local/bin/opencode" "$PATCH_ROOT/usr/local/bin/revenant-opencode" "$PATCH_ROOT/usr/share/applications/opencode.desktop"
rm -f "$PATCH_ROOT/usr/local/bin/pi" "$PATCH_ROOT/usr/local/bin/pi-agent" "$PATCH_ROOT/usr/local/bin/pi-mechanic" "$PATCH_ROOT/usr/local/bin/pi-electronics" "$PATCH_ROOT/usr/local/bin/pi-sysadmin"
rm -f "$PATCH_ROOT/usr/share/applications/pi"*.desktop
rm -rf "$PATCH_ROOT/etc/skel/.config/opencode" "$PATCH_ROOT/home/user/.config/opencode" "$PATCH_ROOT/home/revenant/.config/opencode"
rm -rf "$PATCH_ROOT/etc/skel/.local/state/opencode" "$PATCH_ROOT/home/user/.local/state/opencode" "$PATCH_ROOT/home/revenant/.local/state/opencode"
rm -rf "$PATCH_ROOT/etc/skel/.pi" "$PATCH_ROOT/home/user/.pi" "$PATCH_ROOT/home/revenant/.pi"

# System-wide prompt repository for offline field personas
mkdir -p "$PATCH_ROOT/usr/share/revenant/prompts"

cat << 'PROMPT_MECHANIC_GLOBAL_EOF' > "$PATCH_ROOT/usr/share/revenant/prompts/mechanic.md"
---
description: Automotive & Motor Mechanic Field Diagnostics
argument-hint: "[vehicle-or-DTC-code]"
---
You are the Revenant OS Motor Mechanic Field Diagnostic Agent on a Panasonic Toughbook.
You specialize in automotive diagnostics, OBD-II DTC troubleshooting (P0xxx, P1xxx, Uxxxx, Bxxxx, Cxxxx), CAN bus analysis, diesel/petrol engine mechanical repair, electrical wiring traces, sensor testing (MAF, MAP, O2, TPS, CKP, CMP), starter/alternator/battery load tests, and component replacement sequences.
Provide step-by-step, highly practical diagnostic procedures.
Focus on: $ARGUMENTS
PROMPT_MECHANIC_GLOBAL_EOF

cat << 'PROMPT_ELECTRONICS_GLOBAL_EOF' > "$PATCH_ROOT/usr/share/revenant/prompts/electronics.md"
---
description: Electronics Repair & Circuit Analysis
argument-hint: "[circuit-or-component-fault]"
---
You are the Revenant OS Electronics Diagnostic Specialist on a Panasonic Toughbook.
You specialize in circuit troubleshooting, board-level repair, semiconductor testing (MOSFETs, diodes, transistors, voltage regulators), multimeter/oscilloscope test points, schematic analysis, soldering/rework guidance, and microcontroller firmware (Arduino, ESP32, STM32, PIC).
Provide clear, safe, component-level diagnostic steps and pinout details.
Focus on: $ARGUMENTS
PROMPT_ELECTRONICS_GLOBAL_EOF

cat << 'PROMPT_SYSADMIN_GLOBAL_EOF' > "$PATCH_ROOT/usr/share/revenant/prompts/sysadmin.md"
---
description: Linux Field Engineering & Systems Administration
argument-hint: "[service-or-system-issue]"
---
You are the Revenant OS Field Linux Systems Administrator on a Panasonic Toughbook.
You specialize in Linux system recovery, network diagnostics (ip, ss, tcpdump, ping, ethtool), kernel module troubleshooting, serial interface configuration (/dev/ttyUSB*, /dev/ttyS*), disk and partition repair (fsck, parted, smartctl, dd), systemd service management, and rugged field automation.
Provide exact, reliable terminal commands and concise technical explanations.
Focus on: $ARGUMENTS
PROMPT_SYSADMIN_GLOBAL_EOF

## Create CLI quick-launch aliases pointing to Revenant Agent modes
cat << 'WRAP_MECH' > "$PATCH_ROOT/usr/local/bin/ai-mechanic"
#!/bin/sh
exec /usr/local/bin/revenant-agent --mode mechanic "$@"
WRAP_MECH
chmod +x "$PATCH_ROOT/usr/local/bin/ai-mechanic"

cat << 'WRAP_ELEC' > "$PATCH_ROOT/usr/local/bin/ai-electronics"
#!/bin/sh
exec /usr/local/bin/revenant-agent --mode electronics "$@"
WRAP_ELEC
chmod +x "$PATCH_ROOT/usr/local/bin/ai-electronics"

cat << 'WRAP_SYS' > "$PATCH_ROOT/usr/local/bin/ai-sysadmin"
#!/bin/sh
exec /usr/local/bin/revenant-agent --mode sysadmin "$@"
WRAP_SYS
chmod +x "$PATCH_ROOT/usr/local/bin/ai-sysadmin"

# Single polished desktop launcher: Revenant Field Agent
mkdir -p "$PATCH_ROOT/usr/share/applications"
cat << 'AGENT_DESK_EOF' > "$PATCH_ROOT/usr/share/applications/revenant-agent.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Revenant Field Agent
Comment=Autonomous AI Field Agent (Mechanic, Electronics, SysAdmin, Cloud & Memory)
Exec=xfce4-terminal --title="Revenant Field Agent" --geometry=105x32 -e "/usr/local/bin/revenant-agent"
Icon=utilities-terminal
Terminal=false
Categories=Development;System;Utility;
AGENT_DESK_EOF

for ddir in "$PATCH_ROOT/etc/skel/Desktop" "$PATCH_ROOT/root/Desktop" "$PATCH_ROOT/home/user/Desktop" "$PATCH_ROOT/home/revenant/Desktop"; do
  mkdir -p "$ddir"
  rm -f "$ddir/"pi*.desktop "$ddir/"*opencode*.desktop 2>/dev/null || true
  cp -f "$PATCH_ROOT/usr/share/applications/revenant-agent.desktop" "$ddir/Revenant_Agent.desktop" 2>/dev/null || true
  chmod +x "$ddir/Revenant_Agent.desktop" 2>/dev/null || true
done

# Install Agent Reach and Curated Field Skills
echo "[*] Installing Agent Reach and offline field engineering skills..."
mkdir -p "$PATCH_ROOT/opt/agent-reach" "$PATCH_ROOT/usr/share/revenant/skills"
if [ -d "$SCRIPT_DIR/../agent-reach" ]; then
  cp -a "$SCRIPT_DIR/../agent-reach/"* "$PATCH_ROOT/opt/agent-reach/" 2>/dev/null || true
fi
if [ -d "/opt/agent-reach" ] && [ ! -f "$PATCH_ROOT/opt/agent-reach/pyproject.toml" ]; then
  cp -a /opt/agent-reach/* "$PATCH_ROOT/opt/agent-reach/" 2>/dev/null || true
fi
if [ -d "$SCRIPT_DIR/skills" ]; then
  cp -a "$SCRIPT_DIR/skills/"* "$PATCH_ROOT/usr/share/revenant/skills/" 2>/dev/null || true
fi

chown -R 1001:1001 "$PATCH_ROOT/home/user/.config" 2>/dev/null || true
chown -R 1000:1000 "$PATCH_ROOT/home/revenant/.config" 2>/dev/null || true

echo "[*] Installing streaming /usr/local/bin/ai CLI with voice input support..."
cat << 'PYEOF' > "$PATCH_ROOT/usr/local/bin/ai"
#!/usr/bin/env python3
import sys, os, json, urllib.request, subprocess, re

if len(sys.argv) < 2:
    if os.path.exists("/usr/local/bin/revenant-agent"):
        os.execv("/usr/local/bin/revenant-agent", ["revenant-agent"])
    print("\033[93mUsage: ai <your question or command>\033[0m")
    print("       ai --mic (voice input via microphone)")
    print("Runs 100% locally via Qwen2.5-Coder on llama-server (port 8080).")
    sys.exit(1)

prompt = ""
if sys.argv[1] in ("--mic", "-m", "--voice"):
    print("\033[93m🎙️  [Listening... Speak your query into the microphone (5s)...]\033[0m")
    wav = "/tmp/revenant_ai_voice.wav"
    subprocess.run(f"arecord -q -d 5 -r 16000 -c 1 -f S16_LE '{wav}'", shell=True)
    whisper_bin = "/opt/whisper/whisper-cli"
    model = "/opt/whisper/models/ggml-tiny.en.bin"
    if os.path.exists(whisper_bin) and os.path.exists(model):
        proc = subprocess.run([whisper_bin, "-m", model, "-f", wav, "--no-timestamps", "-nt"], stdout=subprocess.PIPE, text=True)
        raw = proc.stdout.strip()
        prompt = re.sub(r'\[.*?\]', '', raw).strip()
    if not prompt:
        print("\033[91m[!] No speech detected or Whisper not ready.\033[0m")
        sys.exit(1)
    print(f"\033[92m\033[1mVoice Query:\033[0m {prompt}\n")
else:
    prompt = " ".join(sys.argv[1:])

print("\033[96m[Revenant Core: Local Qwen2.5 Thinking (Offline Toughbook CPU)...]\033[0m\n")

payload = json.dumps({
    "model": "default",
    "messages": [
        {"role": "system", "content": "You are the Revenant OS AI Assistant on a Panasonic Toughbook. Give clear, expert, concise Linux and computing answers."},
        {"role": "user", "content": prompt}
    ],
    "temperature": 0.6,
    "max_tokens": 256,
    "stream": True
}).encode('utf-8')

req = urllib.request.Request(
    "http://127.0.0.1:8080/v1/chat/completions",
    data=payload,
    headers={"Content-Type": "application/json"}
)

full_response = []
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        for line in resp:
            line = line.decode('utf-8').strip()
            if not line:
                continue
            if line.startswith("data: "):
                data_str = line[6:]
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                    delta = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    if delta:
                        sys.stdout.write(delta)
                        sys.stdout.flush()
                        full_response.append(delta)
                except json.JSONDecodeError:
                    pass
    print("\n")
    
    answer = "".join(full_response)
    if answer.strip():
        # Clean special chars for Piper TTS audio output
        clean = answer.replace('*', '').replace('`', '').replace('#', '').replace('_', '').replace('"', '').replace("'", "")
        cmd = f"echo '{clean}' | /opt/piper/piper -m /opt/piper/models/en_US-lessac-medium.onnx --output_raw 2>/dev/null | aplay -r 22050 -f S16_LE -t raw - 2>/dev/null"
        subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

except Exception as e:
    print(f"\n\033[91m[!] Local Engine Error: {e}\033[0m")
    print("Make sure llama-server is running: sudo systemctl status llama-server")
PYEOF
chmod +x "$PATCH_ROOT/usr/local/bin/ai"

echo "[*] Installing 'Start AI Stack & Diagnostics' desktop launcher and control script..."
cat << 'STARTEOF' > "$PATCH_ROOT/usr/local/bin/revenant-services"
#!/bin/bash
# ==============================================================================
# Revenant OS - Local AI Engine & Background Services Controller
# ==============================================================================

CYAN="\033[96m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
RESET="\033[0m"
BOLD="\033[1m"

clear
echo -e "${CYAN}${BOLD}"
echo "=========================================================="
echo "    REVENANT OS - LOCAL AI ENGINE & BACKGROUND STACK     "
echo "=========================================================="
echo -e "${RESET}"

echo -e "${CYAN}[*] Checking & Restarting llama-server.service...${RESET}"
sudo systemctl daemon-reload
sudo systemctl restart llama-server.service 2>/dev/null || sudo systemctl start llama-server.service 2>/dev/null || true

echo -e "${CYAN}[*] Checking & Restarting openviking.service...${RESET}"
sudo systemctl restart openviking.service 2>/dev/null || sudo systemctl start openviking.service 2>/dev/null || true

echo -e "${CYAN}[*] Waiting for local model endpoint (http://127.0.0.1:8080/v1)...${RESET}"
echo -e "${CYAN}    (Loading 1.1GB model on Toughbook CPU — this can take up to 90 seconds)${RESET}"
READY=false
for i in {1..90}; do
  if curl -s http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 1
  echo -n "."
done
echo ""

if [ "$READY" = true ]; then
  echo -e "${GREEN}${BOLD}[✓] Local AI Engine is ACTIVE and ready on port 8080!${RESET}"
else
  echo -e "${YELLOW}[!] llama-server has not responded yet. Checking logs...${RESET}"
  echo ""
  sudo journalctl -u llama-server -n 10 --no-pager 2>/dev/null || true
  echo ""
  echo -e "${YELLOW}    If it says 'Illegal instruction' the binary may not support this CPU.${RESET}"
  echo -e "${YELLOW}    If it says 'model not found' run: sudo revenant-update --force${RESET}"
fi

echo ""
echo -e "${CYAN}${BOLD}Service Status Overview:${RESET}"
echo -n "  • llama-server: "
systemctl is-active llama-server.service
echo -n "  • openviking:   "
systemctl is-active openviking.service

echo ""
echo -e "${GREEN}${BOLD}How to interact with your local AI:${RESET}"
echo -e "  1. Universal CLI:     ${BOLD}ai \"What is the IP address of this machine?\"${RESET}"
echo -e "  2. Revenant Agent:    ${BOLD}revenant-agent${RESET} (or simply ${BOLD}ai${RESET})"
echo -e "  3. OpenInterpreter:   ${BOLD}interpreter${RESET}"
echo ""
echo -e "Press [Enter] to launch an interactive Revenant Agent session, or Ctrl+C to exit..."
read -r
revenant-agent
STARTEOF
chmod +x "$PATCH_ROOT/usr/local/bin/revenant-services"

# Deploy instant Voice Assistant helper script
cat << 'VOICE_EOF' > "$PATCH_ROOT/usr/local/bin/revenant-voice"
#!/bin/bash
# ==============================================================================
# Revenant Voice Assistant Single-Window Coordinator (Super+M / Ctrl+Alt+M)
# ==============================================================================

PID=""
if [ -f /tmp/revenant_agent.pid ]; then
  CANDIDATE=$(cat /tmp/revenant_agent.pid 2>/dev/null)
  if [ -n "$CANDIDATE" ] && kill -0 "$CANDIDATE" 2>/dev/null; then
    PID="$CANDIDATE"
  fi
fi

if [ -z "$PID" ]; then
  PID=$(pgrep -f "/usr/local/bin/revenant-agent" | head -n 1)
fi

if [ -n "$PID" ]; then
  # Agent already running: bring existing window to front & trigger microphone directly
  wmctrl -a "Revenant Field Agent" 2>/dev/null || \
  wmctrl -a "Revenant" 2>/dev/null || \
  xdotool search --name "Revenant" windowactivate 2>/dev/null || true

  kill -USR1 "$PID" 2>/dev/null || true
else
  # Agent not running: launch exactly ONE terminal window with microphone active
  exec xfce4-terminal --title="Revenant Field Agent" --geometry=100x30 -e "/usr/local/bin/revenant-agent --mic"
fi
VOICE_EOF
chmod +x "$PATCH_ROOT/usr/local/bin/revenant-voice"

# Create Desktop launchers
for ddir in "$PATCH_ROOT/etc/skel/Desktop" "$PATCH_ROOT/home/user/Desktop" "$PATCH_ROOT/home/revenant/Desktop"; do
  mkdir -p "$ddir"
  cat << 'DESKEOF' > "$ddir/Start_AI_Engine.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Start AI Engine & Services
Comment=Start local inference engine, OpenViking, and open terminal AI
Exec=xfce4-terminal --title="Revenant AI Engine Controller" -e "/usr/local/bin/revenant-services"
Icon=utilities-system-monitor
Terminal=false
StartupNotify=true
Categories=System;Utility;Development;
DESKEOF
  chmod +x "$ddir/Start_AI_Engine.desktop"

  cat << 'AGENTDESK_EOF' > "$ddir/Revenant_Agent.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Revenant Autonomous Agent
Comment=Interactive Field Agent for Panasonic Toughbook
Exec=xfce4-terminal --title="Revenant Field Agent" --geometry=100x30 -e "/usr/local/bin/revenant-agent"
Icon=terminal
Terminal=false
StartupNotify=true
Categories=System;Utility;Development;
AGENTDESK_EOF
  chmod +x "$ddir/Revenant_Agent.desktop"

  cat << 'VOICEDESK_EOF' > "$ddir/Revenant_Voice.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Revenant Voice Assistant (Super+M)
Comment=Talk directly to Revenant Agent using local Whisper STT & Piper TTS
Exec=/usr/local/bin/revenant-voice
Icon=audio-input-microphone
Terminal=false
StartupNotify=true
Categories=AudioVideo;Utility;
VOICEDESK_EOF
  chmod +x "$ddir/Revenant_Voice.desktop"
done

# Create switch-to-i3 and switch-to-xfce utilities
cat << 'I3_SW_EOF' > "$PATCH_ROOT/usr/local/bin/switch-to-i3"
#!/bin/bash
if pgrep -x xfwm4 >/dev/null 2>&1; then
  pkill -9 xfdesktop 2>/dev/null || true
  pkill -9 xfce4-panel 2>/dev/null || true
  pkill -9 xfwm4 2>/dev/null || true
  exec i3 &
else
  exec i3 &
fi
I3_SW_EOF
chmod +x "$PATCH_ROOT/usr/local/bin/switch-to-i3"

cat << 'XFCE_SW_EOF' > "$PATCH_ROOT/usr/local/bin/switch-to-xfce"
#!/bin/bash
pkill -9 i3 2>/dev/null || true
exec xfce4-session &
XFCE_SW_EOF
chmod +x "$PATCH_ROOT/usr/local/bin/switch-to-xfce"

# Deploy i3 Quick Reference & Help script
cat << 'I3_HELP_EOF' > "$PATCH_ROOT/usr/local/bin/revenant-i3-help"
#!/usr/bin/env bash
# Revenant OS i3 Quick Reference & Keyboard Cheat Sheet
set -e

SHOW_TEXT() {
  cat << 'EOF'
================================================================================
           REVENANT OS - i3 WINDOW MANAGER QUICK REFERENCE
================================================================================

 The Mod Key = Windows Key (Super)
 Located between Ctrl and Alt on your Panasonic Toughbook keyboard.

--------------------------------------------------------------------------------
 1. THE ESSENTIAL LIFESAVERS (If you remember nothing else, remember these)
--------------------------------------------------------------------------------
 Mod + Enter            Open a new Terminal
 Mod + d                Open App Launcher (dmenu) - type app name & hit Enter
 Mod + Shift + q        Close the active window (like clicking the red X)
 Mod + m                Activate AI Voice Assistant (microphone prompt)
 Ctrl + Alt + m         Secondary Voice Assistant hotkey
 Mod + F1               Open this Quick Reference guide
 switch-to-xfce         Type in terminal to return to graphical XFCE desktop
 Mod + Shift + e        Log out / Exit i3 (click red bar at top to confirm)

--------------------------------------------------------------------------------
 2. MOVING AROUND (FOCUS & NAVIGATION)
--------------------------------------------------------------------------------
 Mod + Arrow Keys       Move focus to window (Left / Right / Up / Down)
 Mod + j / k / l / ;    Vim-style navigation (Left / Down / Up / Right)
 Mod + Shift + Arrows   Move / shuffle active window to a new position

--------------------------------------------------------------------------------
 3. WINDOW SPLITTING & LAYOUTS
--------------------------------------------------------------------------------
 Mod + v                Vertical Split (next window opens BELOW current window)
 Mod + h                Horizontal Split (next window opens BESIDE current window)
 Mod + f                Toggle Fullscreen mode on / off
 Mod + w                Tabbed Layout (windows become tabs across the top)
 Mod + s                Stacked Layout (windows stack vertically)
 Mod + e                Default Split Layout (return to normal tiling)
 Mod + Shift + Space    Toggle Floating mode (makes window draggable)
 Mod + Left-Click Drag  Move a floating window with mouse
 Mod + Right-Click Drag Resize a floating window with mouse

--------------------------------------------------------------------------------
 4. WORKSPACES (10 CLEAN VIRTUAL DESKTOPS)
--------------------------------------------------------------------------------
 Mod + [1 .. 9]         Jump to Workspace 1 through 9
 Mod + Shift + [1 .. 9] Send current window to Workspace 1 through 9

--------------------------------------------------------------------------------
 5. RESIZING WINDOWS
--------------------------------------------------------------------------------
 1. Press Mod + r (the bar displays [resize]).
 2. Press Arrow Keys to shrink or expand the window.
 3. Press Enter or Escape to lock in the size and exit resize mode.

================================================================================
 Full beginner guide with diagrams: /usr/local/share/doc/revenant-os/06-I3-USER-MANUAL.md
 Online Wiki: https://github.com/Fixitdaz/revenant-os/blob/main/docs/06-I3-USER-MANUAL.md
================================================================================
EOF
}

if [ "$1" = "--cli" ] || [ -t 1 ]; then
  if command -v less >/dev/null 2>&1; then
    SHOW_TEXT | less -R
  else
    SHOW_TEXT
  fi
else
  if command -v xfce4-terminal >/dev/null 2>&1; then
    xfce4-terminal --title="i3 Window Manager Quick Reference (Press Q to exit)" --geometry=88x32 -e "$0 --cli"
  elif command -v zenity >/dev/null 2>&1; then
    SHOW_TEXT | zenity --text-info --title="i3 Window Manager Quick Reference" --width=720 --height=580 --font="Monospace 10" 2>/dev/null || true
  else
    SHOW_TEXT
  fi
fi
I3_HELP_EOF
chmod +x "$PATCH_ROOT/usr/local/bin/revenant-i3-help"
ln -sf /usr/local/bin/revenant-i3-help "$PATCH_ROOT/usr/local/bin/i3-help"

mkdir -p "$PATCH_ROOT/usr/local/share/doc/revenant-os"
if [ -f "$SCRIPT_DIR/docs/06-I3-USER-MANUAL.md" ]; then
  cp -f "$SCRIPT_DIR/docs/06-I3-USER-MANUAL.md" "$PATCH_ROOT/usr/local/share/doc/revenant-os/" 2>/dev/null || true
fi

mkdir -p "$PATCH_ROOT/usr/share/applications"
cat << 'DESK_I3_EOF' > "$PATCH_ROOT/usr/share/applications/switch-to-i3.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Switch to i3 Window Manager
Comment=Switch current desktop session to i3 tiling window manager
Exec=/usr/local/bin/switch-to-i3
Icon=window-manager
Terminal=false
StartupNotify=true
Categories=System;Utility;
DESK_I3_EOF

cat << 'DESK_XFCE_EOF' > "$PATCH_ROOT/usr/share/applications/switch-to-xfce.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Switch to XFCE Desktop
Comment=Switch current desktop session to XFCE graphical desktop
Exec=/usr/local/bin/switch-to-xfce
Icon=xfce4-logo
Terminal=false
StartupNotify=true
Categories=System;Utility;
DESK_XFCE_EOF

for ddir in "$PATCH_ROOT/etc/skel/Desktop" "$PATCH_ROOT/home/user/Desktop" "$PATCH_ROOT/home/revenant/Desktop"; do
  rm -f "$ddir/Switch_to_i3.desktop" "$ddir/Switch_to_XFCE.desktop" "$ddir/switch-to-i3.desktop" "$ddir/switch-to-xfce.desktop" 2>/dev/null || true
done

echo "[*] Configuring desktop dark theme, black top panel & keyboard shortcuts..."
# Deploy GTK3 CSS override for solid black panel and crisp contrast
for u_home in "$PATCH_ROOT/etc/skel" "$PATCH_ROOT/home/user" "$PATCH_ROOT/home/revenant" "$PATCH_ROOT/root"; do
  mkdir -p "$u_home/.config/gtk-3.0"
  cat << 'GTK_CSS' > "$u_home/.config/gtk-3.0/gtk.css"
/* Revenant OS Cyber Dark Desktop & Top Bar */
.xfce4-panel {
    background-color: #0b0f17;
    color: #e2e8f0;
    border-bottom: 1px solid #1e293b;
}
.xfce4-panel button {
    color: #e2e8f0;
    background-color: transparent;
}
.xfce4-panel button:hover {
    background-color: #1e293b;
    color: #00f0ff;
}
.xfce4-panel label {
    color: #e2e8f0;
}
window.xfce4-panel {
    background-color: #0b0f17;
}
GTK_CSS

  mkdir -p "$u_home/.config/xfce4/xfconf/xfce-perchannel-xml"
  cat << 'XSET_EOF' > "$u_home/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
    <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
  </property>
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="96"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
  </property>
</channel>
XSET_EOF

  cat << 'XFWM_EOF' > "$u_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Adwaita-dark"/>
    <property name="title_alignment" type="string" value="left"/>
    <property name="use_compositing" type="bool" value="true"/>
  </property>
</channel>
XFWM_EOF

  cat << 'XFPANEL_EOF' > "$u_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="empty">
    <property name="panel-1" type="empty">
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0.043"/>
        <value type="double" value="0.058"/>
        <value type="double" value="0.090"/>
        <value type="double" value="1.0"/>
      </property>
      <property name="dark-mode" type="bool" value="true"/>
    </property>
  </property>
</channel>
XFPANEL_EOF

  cat << 'SHORTCUTS_EOF' > "$u_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="default" type="empty"/>
    <property name="custom" type="empty">
      <property name="&lt;Super&gt;m" type="string" value="/usr/local/bin/revenant-voice"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;m" type="string" value="/usr/local/bin/revenant-voice"/>
    </property>
  </property>
</channel>
SHORTCUTS_EOF

  mkdir -p "$u_home/.config/i3"
  if [ -f "$PATCH_ROOT/etc/i3/config" ]; then
    cp -f "$PATCH_ROOT/etc/i3/config" "$u_home/.config/i3/config"
  fi
  sed -i '/revenant-voice/d' "$u_home/.config/i3/config" 2>/dev/null || true
  sed -i '/revenant-i3-help/d' "$u_home/.config/i3/config" 2>/dev/null || true
  sed -i '/Revenant OS Voice Assistant Hotkeys/d' "$u_home/.config/i3/config" 2>/dev/null || true
  sed -i '/Revenant OS Hotkeys & Quick Reference/d' "$u_home/.config/i3/config" 2>/dev/null || true
  sed -i '/revenant-agent/d' "$u_home/.config/i3/config" 2>/dev/null || true
  cat << 'I3_HOTKEY' >> "$u_home/.config/i3/config"

# Revenant OS Hotkeys & Quick Reference
bindsym $mod+m exec --no-startup-id /usr/local/bin/revenant-voice
bindsym Mod1+Control+m exec --no-startup-id /usr/local/bin/revenant-voice
bindsym $mod+Shift+a exec --no-startup-id xfce4-terminal --title="Revenant Field Agent" --geometry=105x32 -e "revenant-agent"
bindsym $mod+Shift+m exec --no-startup-id xfce4-terminal --title="Revenant Motor Mechanic" --geometry=105x32 -e "revenant-agent --mode mechanic"
bindsym $mod+Shift+e exec --no-startup-id xfce4-terminal --title="Revenant Electronics Specialist" --geometry=105x32 -e "revenant-agent --mode electronics"
bindsym $mod+Shift+s exec --no-startup-id xfce4-terminal --title="Revenant System Admin" --geometry=105x32 -e "revenant-agent --mode sysadmin"
bindsym $mod+F1 exec --no-startup-id /usr/local/bin/revenant-i3-help
I3_HOTKEY
done

mkdir -p "$PATCH_ROOT/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
cp -f "$PATCH_ROOT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/"*.xml "$PATCH_ROOT/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/" 2>/dev/null || true

# Ensure Toughbook audio capture defaults are unmuted and initialized on login
mkdir -p "$PATCH_ROOT/etc/xdg/autostart"
cat << 'AUDIO_AUTO_EOF' > "$PATCH_ROOT/etc/xdg/autostart/revenant-audio.desktop"
[Desktop Entry]
Type=Application
Name=Revenant Audio Initializer
Exec=sh -c "amixer -q set Capture 95% unmute; amixer -q set 'Capture',0 95% unmute; amixer -q set 'Internal Mic' 95% unmute; amixer -q set 'Mic' 95% unmute; amixer -q set 'Front Mic' 95% unmute; amixer -q set 'Mic Boost' 2 unmute; amixer -q set 'Capture Boost' 2 unmute; amixer -q set 'Input Source' 'Internal Mic' || amixer -q set 'Input Source' 'Mic'; amixer -q sset 'Capture' cap; amixer -q sset 'Internal Mic' cap 2>/dev/null || true"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUDIO_AUTO_EOF

chown -R 1001:1001 "$PATCH_ROOT/home/user" 2>/dev/null || true
chown -R 1000:1000 "$PATCH_ROOT/home/revenant" 2>/dev/null || true

echo "[*] Configuring UFW firewall rules..."
chroot "$PATCH_ROOT" ufw default deny incoming 2>/dev/null || true
chroot "$PATCH_ROOT" ufw default allow outgoing 2>/dev/null || true
chroot "$PATCH_ROOT" ufw allow 22/tcp 2>/dev/null || true
chroot "$PATCH_ROOT" ufw --force enable 2>/dev/null || true
chroot "$PATCH_ROOT" systemctl enable ufw 2>/dev/null || true

echo "[*] Ensuring live environment sudoers and default passwords..."
LIVE_HASH=$(openssl passwd -6 "revenant")
chroot "$PATCH_ROOT" usermod -p "$LIVE_HASH" root 2>/dev/null || true
chroot "$PATCH_ROOT" usermod -p "$LIVE_HASH" user 2>/dev/null || true
chroot "$PATCH_ROOT" usermod -p "$LIVE_HASH" revenant 2>/dev/null || true

mkdir -p "$PATCH_ROOT/etc/sudoers.d"
echo "user ALL=(ALL) NOPASSWD: ALL" > "$PATCH_ROOT/etc/sudoers.d/live-user"
echo "revenant ALL=(ALL) NOPASSWD: ALL" >> "$PATCH_ROOT/etc/sudoers.d/live-user"
echo "%sudo ALL=(ALL) NOPASSWD: ALL" > "$PATCH_ROOT/etc/sudoers.d/99-sudo-group"
chmod 0440 "$PATCH_ROOT/etc/sudoers.d/"*

echo "[*] Installing bulletproof interactive installer into /usr/local/bin/Install_Revenant_OS.sh..."
cat << 'INSTALLER_FIX_EOF' > "$PATCH_ROOT/usr/local/bin/Install_Revenant_OS.sh"
#!/bin/bash
export LC_ALL=C

if [ "$EUID" -ne 0 ]; then
  zenity --error --title="Permission Denied" --text="Please run as root!\nOpen terminal and run: sudo /usr/local/bin/Install_Revenant_OS.sh"
  exit 1
fi

NEW_USER=$(zenity --entry --title="Revenant OS Installer - Step 1 of 4: User Account" \
  --text="Enter your desired username:\n(This will be your primary user account with full administrator access)" \
  --entry-text="revenant")
if [ -z "$NEW_USER" ]; then exit 0; fi

NEW_PASS=""
while [ -z "$NEW_PASS" ]; do
  NEW_PASS=$(zenity --password --title="Revenant OS Installer - Step 2 of 4: User Password" \
    --text="Enter password for user '$NEW_USER':")
  if [ $? -ne 0 ]; then exit 0; fi
  if [ -z "$NEW_PASS" ]; then
    zenity --warning --title="Password Required" --text="Password cannot be empty. Please enter a password."
  fi
done

CONFIRM_PASS=""
while [ "$NEW_PASS" != "$CONFIRM_PASS" ]; do
  CONFIRM_PASS=$(zenity --password --title="Revenant OS Installer - Step 3 of 4: Confirm Password" \
    --text="Confirm password for user '$NEW_USER':")
  if [ $? -ne 0 ]; then exit 0; fi
  if [ "$NEW_PASS" != "$CONFIRM_PASS" ]; then
    zenity --error --title="Password Mismatch" --text="Passwords do not match! Please enter your password again."
    NEW_PASS=$(zenity --password --title="Revenant OS Installer - Step 2 of 4: User Password" \
      --text="Enter password for user '$NEW_USER':")
    if [ $? -ne 0 ]; then exit 0; fi
  fi
done

NEW_HOST=$(zenity --entry --title="Revenant OS Installer - Step 4 of 4: Computer Name" \
  --text="Enter a network name (hostname) for this Toughbook:" \
  --entry-text="revenant-cf52")
if [ -z "$NEW_HOST" ]; then NEW_HOST="revenant-cf52"; fi

DRIVE_OPTS=()
while read -r name size model; do
  [ -z "$name" ] && continue
  DRIVE_OPTS+=("/dev/$name" "$size - $model")
done < <(lsblk -d -n -o NAME,SIZE,MODEL | grep -E "sd|nvme|vd")

if [ ${#DRIVE_OPTS[@]} -eq 0 ]; then
  zenity --error --title="No Drives Found" --text="No suitable drives were detected!"
  exit 1
fi

DRIVE=$(zenity --list --title="Select Target Drive" \
  --text="<b>WARNING: ALL DATA ON THE SELECTED DRIVE WILL BE ERASED!</b>\nSelect the drive to install Revenant OS:" \
  --column="Device" --column="Size & Model" \
  "${DRIVE_OPTS[@]}" \
  --height=320 --width=480 2>/dev/null)

if [ -z "$DRIVE" ]; then
  exit 0
fi

zenity --question --title="Confirm Installation" \
  --text="Are you ABSOLUTELY sure you want to install to <b>$DRIVE</b>?\n\n<b>ALL EXISTING DATA ON $DRIVE WILL BE PERMANENTLY ERASED!</b>" \
  --ok-label="Yes, Erase & Install" --cancel-label="Cancel" || exit 0

LOG="/tmp/revenant_install.log"
echo "=== Revenant OS 1.1 (Build 19.8) Installation Started ===" > "$LOG"
date >> "$LOG"

(
echo "10"; echo "# Formatting drive $DRIVE..."
umount ${DRIVE}* >> "$LOG" 2>&1 || true
swapoff -a >> "$LOG" 2>&1 || true

parted -s "$DRIVE" mklabel msdos >> "$LOG" 2>&1
parted -s -a optimal "$DRIVE" mkpart primary ext4 1MiB 100% >> "$LOG" 2>&1
parted -s "$DRIVE" set 1 boot on >> "$LOG" 2>&1
sync
partprobe "$DRIVE" >> "$LOG" 2>&1 || true
udevadm settle || sleep 2

TARGET_PART="${DRIVE}1"
if [ ! -b "$TARGET_PART" ]; then
  if [ -b "${DRIVE}p1" ]; then
    TARGET_PART="${DRIVE}p1"
  fi
fi

mkfs.ext4 -F -L "RevenantOS" "$TARGET_PART" >> "$LOG" 2>&1
udevadm settle || sleep 1

echo "30"; echo "# Mounting target partition..."
mkdir -p /mnt/target
mount "$TARGET_PART" /mnt/target >> "$LOG" 2>&1

echo "45"; echo "# Copying system files (this will take 2-4 minutes)..."
rsync -aAX \
  --exclude="/dev/*" \
  --exclude="/proc/*" \
  --exclude="/sys/*" \
  --exclude="/tmp/*" \
  --exclude="/run/*" \
  --exclude="/mnt/*" \
  --exclude="/media/*" \
  --exclude="/lost+found" \
  --exclude="/live/*" \
  --exclude="/cdrom/*" \
  / /mnt/target/ >> "$LOG" 2>&1

echo "70"; echo "# Binding system pseudo-filesystems..."
mount --bind /dev /mnt/target/dev
mount --bind /dev/pts /mnt/target/dev/pts
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys
mount --bind /run /mnt/target/run

echo "75"; echo "# Setting up user accounts and credentials..."
chroot /mnt/target groupadd -f sudo
chroot /mnt/target groupadd -f plugdev
chroot /mnt/target groupadd -f netdev
chroot /mnt/target groupadd -f wireshark 2>/dev/null || true

# Ensure primary user exists and has shell/groups
if chroot /mnt/target id "$NEW_USER" &>/dev/null; then
  chroot /mnt/target usermod -s /usr/bin/fish -aG sudo,adm,audio,video,netdev,plugdev,dialout,wireshark "$NEW_USER" >> "$LOG" 2>&1 || true
else
  chroot /mnt/target useradd -m -s /usr/bin/fish -G sudo,adm,audio,video,netdev,plugdev,dialout,wireshark "$NEW_USER" >> "$LOG" 2>&1 || true
fi

# Direct shadow crypt hashing: 100% reliable, immune to PAM chauthtok errors
USER_HASH=$(chroot /mnt/target openssl passwd -6 "$NEW_PASS")
chroot /mnt/target usermod -p "$USER_HASH" "$NEW_USER" >> "$LOG" 2>&1 || true
chroot /mnt/target usermod -p "$USER_HASH" root >> "$LOG" 2>&1 || true
if chroot /mnt/target id "user" &>/dev/null; then
  chroot /mnt/target usermod -p "$USER_HASH" "user" >> "$LOG" 2>&1 || true
fi
if chroot /mnt/target id "revenant" &>/dev/null; then
  chroot /mnt/target usermod -p "$USER_HASH" "revenant" >> "$LOG" 2>&1 || true
fi

# Guaranteed NOPASSWD sudo access for all accounts
mkdir -p /mnt/target/etc/sudoers.d
echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" > "/mnt/target/etc/sudoers.d/99-$NEW_USER"
echo "user ALL=(ALL) NOPASSWD: ALL" > "/mnt/target/etc/sudoers.d/99-user"
echo "revenant ALL=(ALL) NOPASSWD: ALL" > "/mnt/target/etc/sudoers.d/99-revenant"
echo "%sudo ALL=(ALL) NOPASSWD: ALL" > "/mnt/target/etc/sudoers.d/99-sudo-group"
chmod 0440 /mnt/target/etc/sudoers.d/*
sed -i 's/^# *%sudo/%sudo/' /mnt/target/etc/sudoers 2>/dev/null || true

# Copy agent configs to new user's home
if [ -d "/mnt/target/etc/skel/.config/open-interpreter" ]; then
  mkdir -p "/mnt/target/home/$NEW_USER/.config/open-interpreter"
  cp -a /mnt/target/etc/skel/.config/open-interpreter/* "/mnt/target/home/$NEW_USER/.config/open-interpreter/"
fi
chroot /mnt/target chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.config" "/home/$NEW_USER/.local" 2>/dev/null || true

# Ensure Desktop and AI shortcuts exist in installed user home
mkdir -p "/mnt/target/home/$NEW_USER/Desktop"
if [ -f "/mnt/target/etc/skel/Desktop/Start_AI_Engine.desktop" ]; then
  cp -a "/mnt/target/etc/skel/Desktop/Start_AI_Engine.desktop" "/mnt/target/home/$NEW_USER/Desktop/"
  chmod +x "/mnt/target/home/$NEW_USER/Desktop/Start_AI_Engine.desktop"
fi
if [ -f "/mnt/target/etc/skel/Desktop/Revenant_Agent.desktop" ]; then
  cp -a "/mnt/target/etc/skel/Desktop/Revenant_Agent.desktop" "/mnt/target/home/$NEW_USER/Desktop/"
  chmod +x "/mnt/target/home/$NEW_USER/Desktop/Revenant_Agent.desktop"
fi
# Clean up any legacy session switch, opencode, or pi shortcuts from installed desktops
rm -f "/mnt/target/home/$NEW_USER/Desktop/Switch_to_"*.desktop "/mnt/target/home/$NEW_USER/Desktop/switch-to-"*.desktop "/mnt/target/home/$NEW_USER/Desktop/"*opencode*.desktop "/mnt/target/home/$NEW_USER/Desktop/"*OpenCode*.desktop "/mnt/target/home/$NEW_USER/Desktop/"pi*.desktop 2>/dev/null || true
rm -f "/mnt/target/etc/skel/Desktop/Switch_to_"*.desktop "/mnt/target/etc/skel/Desktop/switch-to-"*.desktop "/mnt/target/etc/skel/Desktop/"*opencode*.desktop "/mnt/target/etc/skel/Desktop/"*OpenCode*.desktop "/mnt/target/etc/skel/Desktop/"pi*.desktop 2>/dev/null || true
for ddir in /mnt/target/root/Desktop /mnt/target/home/*/Desktop; do
  rm -f "$ddir/Switch_to_"*.desktop "$ddir/switch-to-"*.desktop "$ddir/"*opencode*.desktop "$ddir/"*OpenCode*.desktop "$ddir/"pi*.desktop 2>/dev/null || true
done
chroot /mnt/target chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/Desktop" 2>/dev/null || true

# Sanitize i3 configuration on target system to eliminate duplicate keybindings & add help hotkey
for i3_cfg in /mnt/target/etc/i3/config /mnt/target/etc/skel/.config/i3/config /mnt/target/home/*/.config/i3/config /mnt/target/root/.config/i3/config; do
  if [ -f "$i3_cfg" ]; then
    sed -i '/revenant-voice/d' "$i3_cfg" 2>/dev/null || true
    sed -i '/revenant-i3-help/d' "$i3_cfg" 2>/dev/null || true
    sed -i '/Revenant OS Voice Assistant Hotkeys/d' "$i3_cfg" 2>/dev/null || true
    sed -i '/Revenant OS Hotkeys & Quick Reference/d' "$i3_cfg" 2>/dev/null || true
    sed -i '/revenant-agent/d' "$i3_cfg" 2>/dev/null || true
    cat << 'I3_HOTKEY' >> "$i3_cfg"

# Revenant OS Hotkeys & Quick Reference
bindsym $mod+m exec --no-startup-id /usr/local/bin/revenant-voice
bindsym Mod1+Control+m exec --no-startup-id /usr/local/bin/revenant-voice
bindsym $mod+Shift+a exec --no-startup-id xfce4-terminal --title="Revenant Field Agent" --geometry=105x32 -e "revenant-agent"
bindsym $mod+Shift+m exec --no-startup-id xfce4-terminal --title="Revenant Motor Mechanic" --geometry=105x32 -e "revenant-agent --mode mechanic"
bindsym $mod+Shift+e exec --no-startup-id xfce4-terminal --title="Revenant Electronics Specialist" --geometry=105x32 -e "revenant-agent --mode electronics"
bindsym $mod+Shift+s exec --no-startup-id xfce4-terminal --title="Revenant System Admin" --geometry=105x32 -e "revenant-agent --mode sysadmin"
bindsym $mod+F1 exec --no-startup-id /usr/local/bin/revenant-i3-help
I3_HOTKEY
  fi
done

# Deploy Revenant "R" avatar and eradicate Debian swirl for installed user
if [ -f /mnt/target/usr/share/icons/revenant-logo.png ]; then
  cp -f /mnt/target/usr/share/icons/revenant-logo.png "/mnt/target/home/$NEW_USER/.face" 2>/dev/null || true
  cp -f /mnt/target/usr/share/icons/revenant-logo.png "/mnt/target/home/$NEW_USER/.face.icon" 2>/dev/null || true
  cp -f /mnt/target/usr/share/icons/revenant-logo.png "/mnt/target/etc/skel/.face" 2>/dev/null || true
  cp -f /mnt/target/usr/share/icons/revenant-logo.png "/mnt/target/etc/skel/.face.icon" 2>/dev/null || true
  cp -f /mnt/target/usr/share/icons/revenant-logo.png "/mnt/target/root/.face" 2>/dev/null || true
  cp -f /mnt/target/usr/share/icons/revenant-logo.png "/mnt/target/root/.face.icon" 2>/dev/null || true
  for uhome in /mnt/target/home/*; do
    if [ -d "$uhome" ]; then
      cp -f /mnt/target/usr/share/icons/revenant-logo.png "$uhome/.face" 2>/dev/null || true
      cp -f /mnt/target/usr/share/icons/revenant-logo.png "$uhome/.face.icon" 2>/dev/null || true
      chroot /mnt/target chown -R "$NEW_USER:$NEW_USER" "$uhome/.face" "$uhome/.face.icon" 2>/dev/null || true
    fi
  done
  mkdir -p /mnt/target/usr/share/images/desktop-base /mnt/target/usr/share/icons/desktop-base
  for av_dest in /mnt/target/usr/share/images/desktop-base/avatar.png /mnt/target/usr/share/icons/desktop-base/avatar.png \
                 /mnt/target/usr/share/images/desktop-base/avatar.svg /mnt/target/usr/share/icons/desktop-base/avatar.svg; do
    cp -f /mnt/target/usr/share/icons/revenant-logo.png "$av_dest" 2>/dev/null || true
  done
fi

# Ensure Toughbook audio capture defaults are unmuted and initialized on installed login
mkdir -p /mnt/target/etc/xdg/autostart
cat << 'AUDIO_AUTO_EOF' > /mnt/target/etc/xdg/autostart/revenant-audio.desktop
[Desktop Entry]
Type=Application
Name=Revenant Audio Initializer
Exec=sh -c "amixer -q set Capture 95% unmute; amixer -q set 'Capture',0 95% unmute; amixer -q set 'Internal Mic' 95% unmute; amixer -q set 'Mic' 95% unmute; amixer -q set 'Front Mic' 95% unmute; amixer -q set 'Mic Boost' 2 unmute; amixer -q set 'Capture Boost' 2 unmute; amixer -q set 'Input Source' 'Internal Mic' || amixer -q set 'Input Source' 'Mic'; amixer -q sset 'Capture' cap; amixer -q sset 'Internal Mic' cap 2>/dev/null || true"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUDIO_AUTO_EOF

echo "$NEW_HOST" > /mnt/target/etc/hostname
cat << HOSTSEOF > /mnt/target/etc/hosts
127.0.0.1   localhost
127.0.1.1   $NEW_HOST
::1         localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTSEOF

# Disable autologin so LightDM displays login greeter on boot
# This gives the user access to their user account and the XFCE/i3 session selector
rm -f /mnt/target/etc/lightdm/lightdm.conf.d/*autologin*.conf
rm -f /mnt/target/etc/lightdm/lightdm.conf.d/*live*.conf
rm -f /mnt/target/etc/lightdm/lightdm.conf.d/*debian*.conf
rm -f /mnt/target/usr/share/lightdm/lightdm.conf.d/*live*.conf
rm -f /mnt/target/usr/share/lightdm/lightdm.conf.d/*autologin*.conf
sed -i -E 's/^[[:space:]]*autologin-user[[:space:]]*=.*/#autologin-user=/' /mnt/target/etc/lightdm/lightdm.conf 2>/dev/null || true
sed -i -E 's/^[[:space:]]*autologin-user-timeout[[:space:]]*=.*/#autologin-user-timeout=/' /mnt/target/etc/lightdm/lightdm.conf 2>/dev/null || true
for cf in /mnt/target/etc/lightdm/lightdm.conf.d/*.conf /mnt/target/usr/share/lightdm/lightdm.conf.d/*.conf; do
  if [ -f "$cf" ]; then
    sed -i -E 's/^[[:space:]]*autologin-user[[:space:]]*=.*/#autologin-user=/' "$cf" 2>/dev/null || true
    sed -i -E 's/^[[:space:]]*autologin-user-timeout[[:space:]]*=.*/#autologin-user-timeout=/' "$cf" 2>/dev/null || true
  fi
done

# Explicitly configure LightDM greeter to show user list and session picker
mkdir -p /mnt/target/etc/lightdm/lightdm.conf.d
cat << 'GREETER_EOF' > /mnt/target/etc/lightdm/lightdm.conf.d/01-revenant-greeter.conf
[Seat:*]
autologin-user=
autologin-guest=false
greeter-session=lightdm-gtk-greeter
greeter-hide-users=false
greeter-show-manual-login=true
user-session=xfce
GREETER_EOF

mkdir -p /mnt/target/etc/lightdm/lightdm-gtk-greeter.conf.d /mnt/target/usr/share/icons

rm -f /mnt/target/etc/lightdm/lightdm-gtk-greeter.conf.d/*debian*.conf 2>/dev/null || true
rm -f /mnt/target/usr/share/lightdm/lightdm-gtk-greeter.conf.d/*debian*.conf 2>/dev/null || true
rm -f /mnt/target/etc/lightdm/lightdm-gtk-greeter.conf.d/01-revenant.conf 2>/dev/null || true

cat << 'GREETER_CONF_EOF' > /mnt/target/etc/lightdm/lightdm-gtk-greeter.conf.d/99_revenant.conf
[greeter]
background = /usr/share/backgrounds/revenant_bootsplash.png
theme-name = Adwaita-dark
icon-theme-name = Papirus-Dark
cursor-theme-name = Adwaita
font-name = Sans 10
xft-antialias = true
xft-dpi = 96
xft-hintstyle = slight
xft-rgba = rgb
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %a, %d %b  %H:%M
default-user-image = /usr/share/icons/revenant-avatar.png
logo = /usr/share/icons/revenant-logo.png
hide-user-image = false
GREETER_CONF_EOF

cat << 'GREETER_MAIN_EOF' > /mnt/target/etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
background = /usr/share/backgrounds/revenant_bootsplash.png
theme-name = Adwaita-dark
icon-theme-name = Papirus-Dark
cursor-theme-name = Adwaita
font-name = Sans 10
xft-antialias = true
xft-dpi = 96
xft-hintstyle = slight
xft-rgba = rgb
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %a, %d %b  %H:%M
default-user-image = /usr/share/icons/revenant-avatar.png
logo = /usr/share/icons/revenant-logo.png
hide-user-image = false
GREETER_MAIN_EOF

# Ensure registered session files exist for both XFCE and i3 in LightDM
mkdir -p /mnt/target/usr/share/xsessions
cat << 'I3_XSESSION' > /mnt/target/usr/share/xsessions/i3.desktop
[Desktop Entry]
Name=i3
Comment=improved dynamic tiling window manager
Exec=i3
TryExec=i3
Type=Application
DesktopNames=i3
Keywords=tiling;wm;windowmanager;window;manager;
I3_XSESSION

if [ ! -f /mnt/target/usr/share/xsessions/xfce.desktop ] && [ -f /mnt/target/usr/share/xsessions/xubuntu.desktop ]; then
  cp /mnt/target/usr/share/xsessions/xubuntu.desktop /mnt/target/usr/share/xsessions/xfce.desktop
fi

rm -f /mnt/target/etc/skel/Desktop/Install*.desktop
rm -f "/mnt/target/home/$NEW_USER/Desktop/Install"*.desktop 2>/dev/null || true
rm -f /mnt/target/home/user/Desktop/Install*.desktop 2>/dev/null || true
rm -f /mnt/target/home/revenant/Desktop/Install*.desktop 2>/dev/null || true

echo "80"; echo "# Generating fstab..."
UUID=$(blkid -s UUID -o value "$TARGET_PART")
cat << FSTABEOF > /mnt/target/etc/fstab
UUID=$UUID /               ext4    errors=remount-ro,noatime 0       1
tmpfs          /tmp            tmpfs   defaults,nosuid,nodev   0       0
FSTABEOF

# Restore update-initramfs divert if live-tools diverted it
chroot /mnt/target dpkg-divert --remove --rename /usr/sbin/update-initramfs >> "$LOG" 2>&1 || true
if [ ! -f /mnt/target/usr/sbin/update-initramfs ] && [ -f /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools ]; then
  cp -a /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools /mnt/target/usr/sbin/update-initramfs
fi
chmod +x /mnt/target/usr/sbin/update-initramfs 2>/dev/null || true

if ! compgen -G "/mnt/target/boot/vmlinuz-*" > /dev/null; then
  for med in /run/live/medium /lib/live/mount/medium /cdrom; do
    if [ -f "$med/live/vmlinuz" ]; then
      cp "$med/live/vmlinuz" /mnt/target/boot/vmlinuz-custom >> "$LOG" 2>&1 || true
      cp "$med/live/initrd.img" /mnt/target/boot/initrd.img-custom >> "$LOG" 2>&1 || true
      break
    fi
  done
fi

chroot /mnt/target apt-get purge -y live-boot live-boot-doc live-config live-config-doc live-config-systemd live-tools >> "$LOG" 2>&1 || true
chroot /mnt/target dpkg-divert --remove --rename /usr/sbin/update-initramfs >> "$LOG" 2>&1 || true
if [ ! -f /mnt/target/usr/sbin/update-initramfs ] && [ -f /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools ]; then
  cp -a /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools /mnt/target/usr/sbin/update-initramfs
fi
chmod +x /mnt/target/usr/sbin/update-initramfs 2>/dev/null || true
# Ensure /boot/config-* exists on installed disk so update-initramfs never fails on missing CONFIG_RD_*
for kimg in /mnt/target/boot/vmlinuz-*; do
  if [ -f "$kimg" ]; then
    kver=$(basename "$kimg" | sed 's/^vmlinuz-//')
    cat << 'CFG_EOF' > "/mnt/target/boot/config-$kver"
CONFIG_RD_GZIP=y
CONFIG_RD_BZIP2=y
CONFIG_RD_LZMA=y
CONFIG_RD_XZ=y
CONFIG_RD_LZO=y
CONFIG_RD_LZ4=y
CONFIG_RD_ZSTD=y
CFG_EOF
  fi
done
cat << 'CFG_EOF' > "/mnt/target/boot/config-6.1.0-50-amd64"
CONFIG_RD_GZIP=y
CONFIG_RD_BZIP2=y
CONFIG_RD_LZMA=y
CONFIG_RD_XZ=y
CONFIG_RD_LZO=y
CONFIG_RD_LZ4=y
CONFIG_RD_ZSTD=y
CFG_EOF

chroot /mnt/target update-initramfs -u -k all >> "$LOG" 2>&1 || true

echo "88"; echo "# Configuring hardened firewall (UFW)..."
chroot /mnt/target ufw default deny incoming >> "$LOG" 2>&1 || true
chroot /mnt/target ufw default allow outgoing >> "$LOG" 2>&1 || true
chroot /mnt/target ufw allow 22/tcp >> "$LOG" 2>&1 || true
chroot /mnt/target ufw --force enable >> "$LOG" 2>&1 || true
chroot /mnt/target systemctl enable ufw >> "$LOG" 2>&1 || true

echo "90"; echo "# Installing GRUB bootloader..."
grub-install --target=i386-pc --boot-directory=/mnt/target/boot --recheck "$DRIVE" >> "$LOG" 2>&1 || true
chroot /mnt/target grub-install --target=i386-pc --recheck "$DRIVE" >> "$LOG" 2>&1 || true
chroot /mnt/target update-grub >> "$LOG" 2>&1 || true

echo "95"; echo "# Writing guaranteed bootloader configuration..."
shopt -s nullglob
VMLINUZ_FILES=(/mnt/target/boot/vmlinuz-*)
INITRD_FILES=(/mnt/target/boot/initrd.img-*)
shopt -u nullglob

if [ ${#VMLINUZ_FILES[@]} -gt 0 ] && [ ${#INITRD_FILES[@]} -gt 0 ]; then
  VMLINUZ=$(basename "${VMLINUZ_FILES[-1]}")
  INITRD=$(basename "${INITRD_FILES[-1]}")

  mkdir -p /mnt/target/boot/grub
  cat << GRUBCFG > /mnt/target/boot/grub/grub.cfg
set default="0"
set timeout=5

insmod part_msdos
insmod ext2
set root='hd0,msdos1'
search --no-floppy --fs-uuid --set=root $UUID

menuentry "Revenant OS 1.1 (Build 19.8) - Agentic Linux" --class debian --class gnu-linux --class gnu --class os {
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $UUID
    linux /boot/$VMLINUZ root=UUID=$UUID ro quiet splash
    initrd /boot/$INITRD
}

menuentry "Revenant OS 1.1 (Build 19.8) (Recovery Mode)" --class debian --class gnu-linux --class gnu --class os {
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $UUID
    linux /boot/$VMLINUZ root=UUID=$UUID ro single
    initrd /boot/$INITRD
}
GRUBCFG
fi

echo "98"; echo "# Finalizing and unmounting..."
sync
mkdir -p /mnt/target/var/log
cp "$LOG" /mnt/target/var/log/revenant_install.log 2>/dev/null || true

umount -l /mnt/target/run 2>/dev/null || true
umount -l /mnt/target/sys 2>/dev/null || true
umount -l /mnt/target/proc 2>/dev/null || true
umount -l /mnt/target/dev/pts 2>/dev/null || true
umount -l /mnt/target/dev 2>/dev/null || true
umount -l /mnt/target 2>/dev/null || true

echo "100"; echo "# Installation Complete!"
) | zenity --progress --title="Installing Revenant OS 1.1 (Build 19.8)" --text="Starting installation..." --percentage=0 --auto-close

if [ -f "$LOG" ] && grep -iq "Installing for i386-pc platform" "$LOG"; then
  zenity --info --title="Success" \
    --text="<b>Revenant OS 1.1 (Build 19.8) has been successfully installed to $DRIVE!</b>\n\nYou can now reboot and remove the USB drive."
else
  zenity --error --title="Error" \
    --text="An error occurred during installation. Check /tmp/revenant_install.log or the target drive."
fi
INSTALLER_FIX_EOF
chmod +x "$PATCH_ROOT/usr/local/bin/Install_Revenant_OS.sh"

echo "[*] Updating version manifest and updater tool..."
mkdir -p "$PATCH_ROOT/etc/revenant" "$PATCH_ROOT/usr/local/bin"
cp "$SCRIPT_DIR/version.json" "$PATCH_ROOT/etc/revenant/version.json"
cp "$SCRIPT_DIR/tools/revenant-update" "$PATCH_ROOT/usr/local/bin/revenant-update"
chmod +x "$PATCH_ROOT/usr/local/bin/revenant-update"

echo "[*] Writing GRUB bootloader configuration for ISO..."
cat << 'EOF' > "$WORKSPACE_DIR/image/boot/grub/grub.cfg"
set default="0"
set timeout=5

insmod png
insmod part_msdos
insmod ext2

if background_image /boot/grub/splash.png; then
  set color_normal=light-gray/black
  set color_highlight=cyan/black
fi

menuentry "Revenant OS 1.1 (Build 19.8) - Unified Field Agent (Offline Voice + Local 3B + OpenViking Memory)" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Revenant OS 1.1 (Build 19.8) (Safe Graphics / Failsafe)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}
EOF

echo "[*] Packaging patched SquashFS (xz compression)..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building 1.1 Build 19.8 ISO with hybrid bootloader..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="1.1 (Build 19.8)"
cp -f "$ISO_TARGET" "$ISO_ALIAS"

echo "[*] Cleaning up workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Build Complete! Revenant OS 1.1 (Build 19.8) ISO ready at: $ISO_TARGET"
ls -lh "$ISO_TARGET" "$ISO_ALIAS"

