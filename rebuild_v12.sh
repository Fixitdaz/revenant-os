#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_rebuild_v12"
PATCH_ROOT="/var/tmp/patch_root_v12"
ISO_SOURCE="$SCRIPT_DIR/revenant_os_toughbook_v11.iso"
ISO_TARGET="$SCRIPT_DIR/revenant_os_toughbook_v12.iso"

echo "[*] Cleaning up temporary mounts..."
umount /mnt/iso 2>/dev/null || true
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Mounting V11 ISO..."
mkdir -p /mnt/iso
mount -o loop,ro "$ISO_SOURCE" /mnt/iso

echo "[*] Unpacking SquashFS..."
unsquashfs -d "$PATCH_ROOT" /mnt/iso/live/filesystem.squashfs

echo "[*] Removing load_video from installer template..."
sed -i '/load_video/d' "$PATCH_ROOT/usr/local/bin/Install_Revenant_OS.sh"

echo "[*] Setting up new ISO image tree..."
mkdir -p "$WORKSPACE_DIR/image/live" "$WORKSPACE_DIR/image/boot/grub"
cp /mnt/iso/live/vmlinuz "$WORKSPACE_DIR/image/live/vmlinuz"
cp /mnt/iso/live/initrd.img "$WORKSPACE_DIR/image/live/initrd.img"

cat << 'EOF' > "$WORKSPACE_DIR/image/boot/grub/grub.cfg"
set default="0"
set timeout=5

menuentry "Revenant OS - Agentic Core" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Revenant OS (Safe Graphics / Failsafe)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}
EOF

echo "[*] Unmounting source V11 ISO..."
umount /mnt/iso

echo "[*] Packaging patched SquashFS..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building V12 ISO..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="V12"

echo "[*] Cleaning up temporary workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Done! V12 ISO ready at: $ISO_TARGET"
