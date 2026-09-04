#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_rebuild_v14"
PATCH_ROOT="/var/tmp/patch_root_v14"
ISO_SOURCE="$SCRIPT_DIR/revenant_os_toughbook_v13.iso"
ISO_TARGET="$SCRIPT_DIR/revenant_os_toughbook_v14.iso"
ASSETS_DIR="$SCRIPT_DIR"

echo "[*] Cleaning up previous mounts and workspace..."
umount /mnt/iso 2>/dev/null || true
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT" /var/tmp/patch_initrd_v14 /var/tmp/patch_initrd_installed

echo "[*] Mounting V13 source ISO..."
mkdir -p /mnt/iso
mount -o loop,ro "$ISO_SOURCE" /mnt/iso

echo "[*] Unpacking SquashFS root..."
unsquashfs -d "$PATCH_ROOT" /mnt/iso/live/filesystem.squashfs

echo "[*] Updating Plymouth Emerald theme with fullscreen Revenant wallpaper..."
for theme_dir in "$PATCH_ROOT/usr/share/plymouth/themes/emerald" "$PATCH_ROOT/usr/share/plymouth/themes/debian-theme"; do
  if [ -d "$theme_dir" ]; then
    cp "$ASSETS_DIR/revenant_bg.png" "$theme_dir/revenant_bg.png"
    cp "$ASSETS_DIR/emerald_original.script" "$theme_dir/emerald.script"
    cp "$ASSETS_DIR/gen_empty.png" "$theme_dir/logo+emerald.png"
    cp "$ASSETS_DIR/gen_empty.png" "$theme_dir/glow.png"
    cp "$ASSETS_DIR/gen_empty.png" "$theme_dir/debian.png"
  fi
done

echo "[*] Patching Live USB initramfs with fullscreen Revenant boot splash..."
mkdir -p /var/tmp/patch_initrd_v14
cd /var/tmp/patch_initrd_v14
zstd -d -c /mnt/iso/live/initrd.img | cpio -idmv >/dev/null 2>&1

if [ -d usr/share/plymouth/themes/emerald ]; then
  cp "$ASSETS_DIR/revenant_bg.png" usr/share/plymouth/themes/emerald/revenant_bg.png
  cp "$ASSETS_DIR/emerald_original.script" usr/share/plymouth/themes/emerald/emerald.script
  cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/logo+emerald.png
  cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/glow.png
  cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/debian.png
fi

echo "[*] Repacking patched Live initramfs..."
mkdir -p "$WORKSPACE_DIR/image/live" "$WORKSPACE_DIR/image/boot/grub"
find . | cpio -H newc -o 2>/dev/null | zstd -19 -T0 -o "$WORKSPACE_DIR/image/live/initrd.img"
cd "$SCRIPT_DIR"
rm -rf /var/tmp/patch_initrd_v14

echo "[*] Patching installed kernel initrd in squashfs root (/boot)..."
shopt -s nullglob
INSTALLED_INITRD_FILES=("$PATCH_ROOT"/boot/initrd.img-*)
shopt -u nullglob

for initrd_path in "${INSTALLED_INITRD_FILES[@]}"; do
  echo "    -> Patching $initrd_path..."
  mkdir -p /var/tmp/patch_initrd_installed
  cd /var/tmp/patch_initrd_installed
  zstd -d -c "$initrd_path" | cpio -idmv >/dev/null 2>&1
  if [ -d usr/share/plymouth/themes/emerald ]; then
    cp "$ASSETS_DIR/revenant_bg.png" usr/share/plymouth/themes/emerald/revenant_bg.png
    cp "$ASSETS_DIR/emerald_original.script" usr/share/plymouth/themes/emerald/emerald.script
    cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/logo+emerald.png
    cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/glow.png
    cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/debian.png
  fi
  find . | cpio -H newc -o 2>/dev/null | zstd -19 -T0 -f -o "$initrd_path"
  cd "$SCRIPT_DIR"
  rm -rf /var/tmp/patch_initrd_installed
done

echo "[*] Setting up Live GRUB configuration and background..."
cp /mnt/iso/live/vmlinuz "$WORKSPACE_DIR/image/live/vmlinuz"
cp "$ASSETS_DIR/revenant_bg.png" "$WORKSPACE_DIR/image/boot/grub/splash.png"

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

menuentry "Revenant OS - Agentic Core" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Revenant OS (Safe Graphics / Failsafe)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}
EOF

echo "[*] Unmounting source V13 ISO..."
umount /mnt/iso

echo "[*] Packaging patched SquashFS..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building V14 ISO with hybrid bootloader..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="V14"

echo "[*] Cleaning up temporary workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Done! Revenant OS V14 ISO ready at: $ISO_TARGET"
ls -lh "$ISO_TARGET"
