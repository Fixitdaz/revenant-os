#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_rebuild_v15"
PATCH_ROOT="/var/tmp/patch_root_v15"
ISO_SOURCE="$SCRIPT_DIR/revenant_os_toughbook_v14.iso"
ISO_TARGET="$SCRIPT_DIR/revenant_os_toughbook_v15.iso"
CACHE_DIR="/var/tmp/revenant_cache"

echo "[*] Cleaning up previous mounts and temporary directories..."
umount /mnt/iso 2>/dev/null || true
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"
mkdir -p "$CACHE_DIR"

echo "[*] Mounting V14 source ISO..."
mkdir -p /mnt/iso
mount -o loop,ro "$ISO_SOURCE" /mnt/iso

echo "[*] Unpacking SquashFS root..."
unsquashfs -d "$PATCH_ROOT" /mnt/iso/live/filesystem.squashfs

echo "[*] Setting up ISO base image tree..."
mkdir -p "$WORKSPACE_DIR/image/live" "$WORKSPACE_DIR/image/boot/grub"
cp /mnt/iso/live/vmlinuz "$WORKSPACE_DIR/image/live/vmlinuz"
cp /mnt/iso/live/initrd.img "$WORKSPACE_DIR/image/live/initrd.img"
if [ -f /mnt/iso/boot/grub/splash.png ]; then
  cp /mnt/iso/boot/grub/splash.png "$WORKSPACE_DIR/image/boot/grub/splash.png"
fi

echo "[*] Unmounting source V14 ISO..."
umount /mnt/iso

echo "[*] Fetching llama-server binary..."
mkdir -p "$PATCH_ROOT/opt/llama.cpp"
if [ ! -f "$CACHE_DIR/llama-server" ]; then
  echo "    -> Downloading llama.cpp release b10816..."
  mkdir -p /tmp/llama_dl
  curl -fsSL -o /tmp/llama_dl/llama.tar.gz https://github.com/ggerganov/llama.cpp/releases/download/b10816/llama-b10816-bin-ubuntu-x64.tar.gz
  tar -xzf /tmp/llama_dl/llama.tar.gz -C /tmp/llama_dl/
  find /tmp/llama_dl -name "llama-server" -exec cp {} "$CACHE_DIR/llama-server" \;
  rm -rf /tmp/llama_dl
fi
cp "$CACHE_DIR/llama-server" "$PATCH_ROOT/opt/llama.cpp/llama-server"
chmod +x "$PATCH_ROOT/opt/llama.cpp/llama-server"

echo "[*] Fetching Qwen2.5-Coder-1.5B model..."
mkdir -p "$PATCH_ROOT/opt/models"
if [ ! -f "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" ]; then
  echo "    -> Downloading Qwen2.5-Coder-1.5B (~1.04 GB) from HuggingFace..."
  curl -L --progress-bar -o "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" \
    https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf
fi
cp "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" "$PATCH_ROOT/opt/models/"

echo "[*] Installing systemd services for llama-server and OpenViking..."
cat << 'SVCEOF' > "$PATCH_ROOT/etc/systemd/system/llama-server.service"
[Unit]
Description=Revenant OS Local Llama Inference Server
After=network.target

[Service]
Type=simple
ExecStart=/opt/llama.cpp/llama-server --model /opt/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf --host 127.0.0.1 --port 8080 --ctx-size 2048 --threads 2 --n-gpu-layers 0
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

cat << 'VKEOF' > "$PATCH_ROOT/etc/systemd/system/openviking.service"
[Unit]
Description=OpenViking Automated Agent Context & Memory Daemon
After=llama-server.service

[Service]
Type=simple
ExecStart=/usr/local/bin/ov daemon --host 127.0.0.1 --port 8080
Restart=always
RestartSec=5
User=root
Environment=OPENAI_API_BASE=http://127.0.0.1:8080/v1
Environment=OPENAI_API_KEY=sk-local-revenant

[Install]
WantedBy=multi-user.target
VKEOF

# Enable services in multi-user target
mkdir -p "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/llama-server.service "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants/llama-server.service"
ln -sf /etc/systemd/system/openviking.service "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants/openviking.service"

echo "[*] Updating /usr/local/bin/ai with offline local inference and speech..."
cat << 'PYEOF' > "$PATCH_ROOT/usr/local/bin/ai"
#!/usr/bin/env python3
import sys, json, urllib.request, subprocess

if len(sys.argv) < 2:
    print("\033[93mUsage: ai <your question or command>\033[0m")
    print("Runs 100% locally via Qwen2.5-Coder on llama-server (port 8080).")
    sys.exit(1)

prompt = " ".join(sys.argv[1:])
print("\033[96m[Revenant Core: Local Qwen2.5 Thinking...]\033[0m")

payload = json.dumps({
    "model": "qwen2.5-coder-1.5b-instruct",
    "messages": [
        {"role": "system", "content": "You are the Revenant OS AI Assistant on a Panasonic Toughbook. Give clear, expert Linux and computing answers."},
        {"role": "user", "content": prompt}
    ],
    "temperature": 0.6,
    "max_tokens": 512
}).encode('utf-8')

req = urllib.request.Request(
    "http://127.0.0.1:8080/v1/chat/completions",
    data=payload,
    headers={"Content-Type": "application/json"}
)

try:
    with urllib.request.urlopen(req, timeout=40) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        answer = res["choices"][0]["message"]["content"]
        print("\n" + answer + "\n")
        
        clean = answer.replace('*', '').replace('`', '').replace('#', '').replace('_', '').replace('"', '').replace("'", "")
        cmd = f"echo '{clean}' | /opt/piper/piper -m /opt/piper/models/en_US-lessac-medium.onnx --output_raw | aplay -r 22050 -f S16_LE -t raw -"
        subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except Exception as e:
    print(f"\033[91m[!] Local Engine Error: {e}\033[0m")
    print("Make sure llama-server is running: sudo systemctl status llama-server")
PYEOF
chmod +x "$PATCH_ROOT/usr/local/bin/ai"

echo "[*] Setting default agent environment variables..."
sed -i '/OPENAI_API_BASE/d' "$PATCH_ROOT/etc/environment" 2>/dev/null || true
sed -i '/OPENAI_API_KEY/d' "$PATCH_ROOT/etc/environment" 2>/dev/null || true
echo 'OPENAI_API_BASE="http://127.0.0.1:8080/v1"' >> "$PATCH_ROOT/etc/environment"
echo 'OPENAI_API_KEY="sk-local-revenant"' >> "$PATCH_ROOT/etc/environment"

echo "[*] Installing updater and manifest into /etc/revenant and /usr/local/bin..."
mkdir -p "$PATCH_ROOT/etc/revenant" "$PATCH_ROOT/usr/local/bin"
cp "$SCRIPT_DIR/version.json" "$PATCH_ROOT/etc/revenant/version.json"
cp "$SCRIPT_DIR/tools/revenant-update" "$PATCH_ROOT/usr/local/bin/revenant-update"
chmod +x "$PATCH_ROOT/usr/local/bin/revenant-update"

echo "[*] Copying GRUB bootloader configuration..."
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

menuentry "Revenant OS - Agentic Core (Offline Local LLM)" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Revenant OS (Safe Graphics / Failsafe)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}
EOF

echo "[*] Packaging patched SquashFS (xz compression)..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building V15 ISO with hybrid bootloader..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="V15"

echo "[*] Cleaning up workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Build Complete! Revenant OS V15 ISO ready at: $ISO_TARGET"
ls -lh "$ISO_TARGET"
