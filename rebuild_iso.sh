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
ISO_TARGET="$SCRIPT_DIR/revenant_os_1.1_build18.3.iso"
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
  ufw

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
if [ -f "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" ] && [ ! -f "$PATCH_ROOT/opt/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" ]; then
  echo "[*] Copying Qwen2.5-Coder-1.5B model into squashfs root..."
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
ExecStart=/opt/llama.cpp/llama-server --model /opt/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf --alias qwen2.5-coder-1.5b-instruct --host 127.0.0.1 --port 8080 --ctx-size 4096 --threads 2 -np 1 --no-cache-prompt -sps 0 --n-gpu-layers 0
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
# Revenant OS - Native Autonomous Agent Core (CPU-Optimized for Panasonic Toughbook)
# ==============================================================================
import sys, os, json, re, urllib.request, subprocess, glob, time, signal, atexit
try:
    import readline
except ImportError:
    readline = None

CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"

SYSTEM_PROMPT = """You are the Revenant OS Autonomous Agent on a Panasonic Toughbook.
You are concise, highly practical, and expert in Linux systems.
You can inspect the system and run actions using these commands:
- [EXEC: bash_command] to execute terminal commands (e.g. [EXEC: df -h], [EXEC: ip a])
- [READ: filepath] to view file contents
- [WRITE: filepath | content] to create or update files
Keep explanations brief. Provide the command needed to solve the user's task."""

PID_FILE = "/tmp/revenant_agent.pid"
VOICE_ENABLED = False
mic_requested = False

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

def handle_voice_signal(signum, frame):
    global mic_requested
    mic_requested = True
    raise VoiceTrigger()

try:
    signal.signal(signal.SIGUSR1, handle_voice_signal)
    signal.siginterrupt(signal.SIGUSR1, True)
except Exception:
    pass

def set_input_buffer(text):
    """Prefill the interactive readline prompt so user can review/edit and hit Enter."""
    if not text or not readline:
        return
    def pre_hook():
        try:
            readline.insert_text(text)
            readline.redisplay()
        except Exception:
            pass
        try:
            readline.set_pre_input_hook(None)
        except Exception:
            pass
    try:
        readline.set_pre_input_hook(pre_hook)
    except Exception:
        pass

def speak_text(text):
    if not VOICE_ENABLED:
        return
    clean = re.sub(r'\[.*?\]', '', text)
    clean = re.sub(r'[*`#_"\']', '', clean).strip()
    if clean:
        cmd = f"echo '{clean}' | /opt/piper/piper -m /opt/piper/models/en_US-lessac-medium.onnx --output_raw 2>/dev/null | aplay -r 22050 -f S16_LE -t raw - 2>/dev/null"
        subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def configure_microphone():
    """Unmute and boost Panasonic Toughbook CF-52 microphone capture channels."""
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
    """Record audio from Toughbook microphone using arecord (16kHz 16-bit mono for Whisper)."""
    configure_microphone()
    try:
        if os.path.exists(output_wav):
            try:
                os.remove(output_wav)
            except Exception:
                pass
        print(f"\n{YELLOW}🎙️  [Listening... Speak into microphone ({duration}s)...]{RESET}")

        # Primary attempt: default ALSA / Pulse / Pipewire
        cmd = f"arecord -q -d {duration} -r 16000 -c 1 -f S16_LE '{output_wav}'"
        res = subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # Fallback 1: plughw:0,0
        if res.returncode != 0 or not os.path.exists(output_wav) or os.path.getsize(output_wav) < 1000:
            cmd = f"arecord -q -D plughw:0,0 -d {duration} -r 16000 -c 1 -f S16_LE '{output_wav}'"
            res = subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # Fallback 2: stereo capture with downmix
        if res.returncode != 0 or not os.path.exists(output_wav) or os.path.getsize(output_wav) < 1000:
            cmd = f"arecord -q -d {duration} -r 16000 -c 2 -f S16_LE /tmp/revenant_stereo.wav && (ffmpeg -y -i /tmp/revenant_stereo.wav -ac 1 '{output_wav}' 2>/dev/null || cp /tmp/revenant_stereo.wav '{output_wav}')"
            subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        return os.path.exists(output_wav) and os.path.getsize(output_wav) > 1000
    except Exception as e:
        print(f"{RED}[!] Audio record error: {e}{RESET}")
        return False

def transcribe_voice(wav_path="/tmp/revenant_voice.wav"):
    """Transcribe audio locally using whisper.cpp (ggml-tiny.en)."""
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
            clean = re.sub(r'\[.*?\]', '', raw).strip()
            return clean
        except Exception as e:
            print(f"{RED}[!] Whisper error: {e}{RESET}")

    try:
        from pywhispercpp.model import Model
        m = Model('tiny.en', models_dir='/opt/whisper/models')
        segs = m.transcribe(wav_path)
        return " ".join([s.text for s in segs]).strip()
    except Exception:
        pass

    print(f"{YELLOW}[!] Whisper STT not ready. Run 'sudo revenant-update' to install.{RESET}")
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
        print(f"{RED}[!] Could not capture audio from microphone. Check connections.{RESET}\n")
    return ""

def get_system_telemetry():
    telemetry = []
    bats = glob.glob('/sys/class/power_supply/BAT*/capacity')
    if bats:
        try:
            with open(bats[0]) as f:
                cap = f.read().strip()
            telemetry.append(f"Battery: {cap}%")
        except Exception:
            pass
    temps = glob.glob('/sys/class/thermal/thermal_zone*/temp')
    if temps:
        try:
            with open(temps[0]) as f:
                t = int(f.read().strip()) / 1000.0
            telemetry.append(f"Temp: {t:.1f}°C")
        except Exception:
            pass
    try:
        out = subprocess.check_output("free -m | awk '/Mem:/ {print $3\"/\"$2\"MB\"}'", shell=True).decode().strip()
        telemetry.append(f"RAM: {out}")
    except Exception:
        pass
    return " | ".join(telemetry)

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

def call_local_model(messages, max_tokens=384):
    payload = json.dumps({
        "model": "qwen2.5-coder-1.5b-instruct",
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
                        collected.append(delta)
                except json.JSONDecodeError:
                    pass
    print()
    return "".join(collected)

def run_agent_loop(initial_prompt=None, initial_mic=False):
    global VOICE_ENABLED, mic_requested
    os.system('clear')
    print(f"{CYAN}{BOLD}=========================================================={RESET}")
    print(f"{CYAN}{BOLD}        REVENANT OS - AUTONOMOUS FIELD AGENT CORE         {RESET}")
    print(f"{CYAN}{BOLD}=========================================================={RESET}")
    telem = get_system_telemetry()
    if telem:
        print(f"{DIM}{telem}{RESET}")
    print(f"{DIM}Commands: /mic (voice input) | /voice (toggle speech) | /sys | /clear | exit{RESET}")
    print(f"{CYAN}Hotkeys:  Press <Super>+M anytime to speak directly into this window.{RESET}\n")

    history = [
        {"role": "system", "content": SYSTEM_PROMPT}
    ]

    pending_user_input = initial_prompt

    if initial_mic:
        handle_mic_input()

    while True:
        if mic_requested:
            mic_requested = False
            handle_mic_input()

        if pending_user_input:
            user_input = pending_user_input
            pending_user_input = None
        else:
            try:
                user_input = input(f"{GREEN}{BOLD}revenant ❯ {RESET}").strip()
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

        if user_input.lower() in ('exit', 'quit', ':q'):
            print(f"{YELLOW}Exiting Revenant Agent. Goodbye!{RESET}")
            break
        elif user_input.lower() in ('/mic', '/talk', '/listen'):
            handle_mic_input()
            continue
        elif user_input == '/clear':
            history = [{"role": "system", "content": SYSTEM_PROMPT}]
            print(f"{GREEN}[✓] Conversation memory cleared.{RESET}\n")
            continue
        elif user_input == '/voice':
            VOICE_ENABLED = not VOICE_ENABLED
            state = "ENABLED" if VOICE_ENABLED else "DISABLED"
            print(f"{CYAN}[*] Voice speech synthesis is now {state}.{RESET}\n")
            continue
        elif user_input == '/sys':
            print(f"\n{CYAN}{BOLD}Toughbook Hardware Diagnostics:{RESET}")
            subprocess.run("uname -a; uptime; free -h; df -h /; sensors 2>/dev/null || true", shell=True)
            print()
            continue

        history.append({"role": "user", "content": user_input})

        if len(history) > 10:
            history = [history[0]] + history[-8:]

        print(f"\n{CYAN}[Revenant Agent Thinking...]{RESET}")
        try:
            response = call_local_model(history)
            history.append({"role": "assistant", "content": response})
            speak_text(response)

            tool_matches = re.findall(r'\[(EXEC|READ|WRITE):\s*(.*?)\]', response, re.DOTALL)
            for action_type, payload in tool_matches:
                result = execute_tool(action_type, payload)
                history.append({"role": "user", "content": f"Tool execution result:\n{result}"})
                print(f"\n{CYAN}[Revenant Agent Analyzing Result...]{RESET}")
                followup = call_local_model(history, max_tokens=256)
                history.append({"role": "assistant", "content": followup})
                speak_text(followup)

            print()

        except urllib.error.URLError as e:
            print(f"\n{RED}[!] Cannot connect to local inference server: {e}{RESET}")
            print(f"{YELLOW}Ensure llama-server is active: sudo systemctl restart llama-server{RESET}\n")
        except Exception as e:
            print(f"\n{RED}[!] Agent Error: {e}{RESET}\n")

if __name__ == '__main__':
    initial = None
    start_mic = False
    if len(sys.argv) > 1:
        if sys.argv[1] in ('--mic', '-m', '--voice'):
            VOICE_ENABLED = True
            start_mic = True
        else:
            initial = " ".join(sys.argv[1:])
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
    "model": "qwen2.5-coder-1.5b-instruct",
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
  cat << 'I3_HOTKEY' >> "$u_home/.config/i3/config"

# Revenant OS Hotkeys & Quick Reference
bindsym $mod+m exec --no-startup-id /usr/local/bin/revenant-voice
bindsym Mod1+Control+m exec --no-startup-id /usr/local/bin/revenant-voice
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
echo "=== Revenant OS 1.0 (Build 17) Installation Started ===" > "$LOG"
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
  chroot /mnt/target chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.config" 2>/dev/null || true
fi

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
# Clean up any legacy session switch shortcuts from installed desktops (LightDM greeter handles session selection)
rm -f "/mnt/target/home/$NEW_USER/Desktop/Switch_to_"*.desktop "/mnt/target/home/$NEW_USER/Desktop/switch-to-"*.desktop 2>/dev/null || true
rm -f "/mnt/target/etc/skel/Desktop/Switch_to_"*.desktop "/mnt/target/etc/skel/Desktop/switch-to-"*.desktop 2>/dev/null || true
for ddir in /mnt/target/root/Desktop /mnt/target/home/*/Desktop; do
  rm -f "$ddir/Switch_to_"*.desktop "$ddir/switch-to-"*.desktop 2>/dev/null || true
done
chroot /mnt/target chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/Desktop" 2>/dev/null || true

# Sanitize i3 configuration on target system to eliminate duplicate keybindings & add help hotkey
for i3_cfg in /mnt/target/etc/i3/config /mnt/target/etc/skel/.config/i3/config /mnt/target/home/*/.config/i3/config /mnt/target/root/.config/i3/config; do
  if [ -f "$i3_cfg" ]; then
    sed -i '/revenant-voice/d' "$i3_cfg" 2>/dev/null || true
    sed -i '/revenant-i3-help/d' "$i3_cfg" 2>/dev/null || true
    sed -i '/Revenant OS Voice Assistant Hotkeys/d' "$i3_cfg" 2>/dev/null || true
    sed -i '/Revenant OS Hotkeys & Quick Reference/d' "$i3_cfg" 2>/dev/null || true
    cat << 'I3_HOTKEY' >> "$i3_cfg"

# Revenant OS Hotkeys & Quick Reference
bindsym $mod+m exec --no-startup-id /usr/local/bin/revenant-voice
bindsym Mod1+Control+m exec --no-startup-id /usr/local/bin/revenant-voice
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

menuentry "Revenant OS 1.1 (Build 18.3) - Agentic Linux" --class debian --class gnu-linux --class gnu --class os {
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $UUID
    linux /boot/$VMLINUZ root=UUID=$UUID ro quiet splash
    initrd /boot/$INITRD
}

menuentry "Revenant OS 1.1 (Build 18.3) (Recovery Mode)" --class debian --class gnu-linux --class gnu --class os {
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
) | zenity --progress --title="Installing Revenant OS 1.1 (Build 18.3)" --text="Starting installation..." --percentage=0 --auto-close

if [ -f "$LOG" ] && grep -iq "Installing for i386-pc platform" "$LOG"; then
  zenity --info --title="Success" \
    --text="<b>Revenant OS 1.1 (Build 18.3) has been successfully installed to $DRIVE!</b>\n\nYou can now reboot and remove the USB drive."
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

menuentry "Revenant OS 1.1 (Build 18.3) - Agentic Core (Offline Voice + Local LLM)" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Revenant OS 1.1 (Build 18.3) (Safe Graphics / Failsafe)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}
EOF

echo "[*] Packaging patched SquashFS (xz compression)..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building 1.1 Build 18.3 ISO with hybrid bootloader..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="1.1"
cp -f "$ISO_TARGET" "$ISO_ALIAS"

echo "[*] Cleaning up workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Build Complete! Revenant OS 1.1 (Build 18.3) ISO ready at: $ISO_TARGET"
ls -lh "$ISO_TARGET" "$ISO_ALIAS"

