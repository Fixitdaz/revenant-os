#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_rebuild_v13"
PATCH_ROOT="/var/tmp/patch_root_v13"
ISO_SOURCE="$SCRIPT_DIR/revenant_os_toughbook_v12.iso"
ISO_TARGET="$SCRIPT_DIR/revenant_os_toughbook_v13.iso"
ASSETS_DIR="$SCRIPT_DIR"

echo "[*] Cleaning up previous mounts and workspace..."
umount /mnt/iso 2>/dev/null || true
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT" /var/tmp/patch_initrd_v13 /var/tmp/patch_initrd_installed

echo "[*] Mounting V12 source ISO..."
mkdir -p /mnt/iso
mount -o loop,ro "$ISO_SOURCE" /mnt/iso

echo "[*] Unpacking SquashFS root..."
unsquashfs -d "$PATCH_ROOT" /mnt/iso/live/filesystem.squashfs

echo "[*] Applying Revenant OS System Identification..."
cat << 'EOF' > "$PATCH_ROOT/etc/os-release"
PRETTY_NAME="Revenant OS 1.0 (Agentic Linux)"
NAME="Revenant OS"
VERSION_ID="1.0"
VERSION="1.0 (Emerald)"
VERSION_CODENAME=emerald
ID=revenant
ID_LIKE=debian
HOME_URL="https://revenantos.ai/"
SUPPORT_URL="https://revenantos.ai/"
BUG_REPORT_URL="https://revenantos.ai/"
EOF

echo -e "Revenant OS 1.0 (Agentic Linux) \\n \\l\n" > "$PATCH_ROOT/etc/issue"
echo -e "Revenant OS 1.0 (Agentic Linux) \\n \\l\n" > "$PATCH_ROOT/etc/issue.net"

echo "[*] Replacing Plymouth boot splash theme assets..."
for theme_dir in "$PATCH_ROOT/usr/share/plymouth/themes/emerald" "$PATCH_ROOT/usr/share/plymouth/themes/debian-theme"; do
  if [ -d "$theme_dir" ]; then
    cp "$ASSETS_DIR/gen_logo_emerald.png" "$theme_dir/logo+emerald.png"
    cp "$ASSETS_DIR/gen_glow.png" "$theme_dir/glow.png"
    cp "$ASSETS_DIR/gen_empty.png" "$theme_dir/debian.png"
  fi
done

if [ -f "$PATCH_ROOT/usr/share/plymouth/debian-logo.png" ]; then
  cp "$ASSETS_DIR/gen_skull_256.png" "$PATCH_ROOT/usr/share/plymouth/debian-logo.png"
fi

echo "[*] Replacing GRUB bootloader background images..."
# All desktop-base grub backgrounds
find "$PATCH_ROOT/usr/share/desktop-base" -name "grub-16x9.png" -exec cp "$ASSETS_DIR/gen_grub_16x9.png" "{}" \;
find "$PATCH_ROOT/usr/share/desktop-base" -name "grub-4x3.png" -exec cp "$ASSETS_DIR/gen_grub_4x3.png" "{}" \;

find "$PATCH_ROOT/usr/share/desktop-base" -name "*login*.svg" -exec cp "$ASSETS_DIR/gen_grub_16x9.png" "{}" \; 2>/dev/null || true
if [ -f "$PATCH_ROOT/usr/share/images/desktop-base/desktop-grub.png" ]; then
  rm -f "$PATCH_ROOT/usr/share/images/desktop-base/desktop-grub.png"
  cp "$ASSETS_DIR/gen_grub_16x9.png" "$PATCH_ROOT/usr/share/images/desktop-base/desktop-grub.png"
fi

echo "[*] Replacing vendor debian-logos with Revenant skull badges..."
LOGO_DIR="$PATCH_ROOT/usr/share/desktop-base/debian-logos"
if [ -d "$LOGO_DIR" ]; then
  cp "$ASSETS_DIR/gen_skull_64.png" "$LOGO_DIR/logo-64.png"
  cp "$ASSETS_DIR/gen_skull_128.png" "$LOGO_DIR/logo-128.png"
  cp "$ASSETS_DIR/gen_skull_256.png" "$LOGO_DIR/logo-256.png"
  cp "$ASSETS_DIR/gen_skull_256.png" "$LOGO_DIR/logo.png" 2>/dev/null || true
  cp "$ASSETS_DIR/gen_logo_text_64.png" "$LOGO_DIR/logo-text-64.png"
  cp "$ASSETS_DIR/gen_logo_text_128.png" "$LOGO_DIR/logo-text-128.png"
  cp "$ASSETS_DIR/gen_logo_text_256.png" "$LOGO_DIR/logo-text-256.png"
  cp "$ASSETS_DIR/gen_logo_text_64.png" "$LOGO_DIR/logo-text-version-64.png"
  cp "$ASSETS_DIR/gen_logo_text_128.png" "$LOGO_DIR/logo-text-version-128.png"
  cp "$ASSETS_DIR/gen_logo_text_256.png" "$LOGO_DIR/logo-text-version-256.png"
fi

if [ -f "$PATCH_ROOT/usr/share/pixmaps/debian-logo.png" ]; then
  cp "$ASSETS_DIR/gen_skull_256.png" "$PATCH_ROOT/usr/share/pixmaps/debian-logo.png"
fi

find "$PATCH_ROOT/usr/share/icons" -name "start-here.png" -exec cp "$ASSETS_DIR/gen_skull_256.png" "{}" \; 2>/dev/null || true

echo "[*] Patching Live USB initramfs with Revenant boot splash..."
mkdir -p /var/tmp/patch_initrd_v13
cd /var/tmp/patch_initrd_v13
zstd -d -c /mnt/iso/live/initrd.img | cpio -idmv >/dev/null 2>&1

if [ -d usr/share/plymouth/themes/emerald ]; then
  cp "$ASSETS_DIR/gen_logo_emerald.png" usr/share/plymouth/themes/emerald/logo+emerald.png
  cp "$ASSETS_DIR/gen_glow.png" usr/share/plymouth/themes/emerald/glow.png
  cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/debian.png
fi
if [ -f usr/share/plymouth/debian-logo.png ]; then
  cp "$ASSETS_DIR/gen_skull_256.png" usr/share/plymouth/debian-logo.png
fi
if [ -f etc/os-release ]; then
  cp "$PATCH_ROOT/etc/os-release" etc/os-release
fi

echo "[*] Repacking patched Live initramfs..."
mkdir -p "$WORKSPACE_DIR/image/live" "$WORKSPACE_DIR/image/boot/grub"
find . | cpio -H newc -o 2>/dev/null | zstd -19 -T0 -o "$WORKSPACE_DIR/image/live/initrd.img"
cd "$SCRIPT_DIR"
rm -rf /var/tmp/patch_initrd_v13

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
    cp "$ASSETS_DIR/gen_logo_emerald.png" usr/share/plymouth/themes/emerald/logo+emerald.png
    cp "$ASSETS_DIR/gen_glow.png" usr/share/plymouth/themes/emerald/glow.png
    cp "$ASSETS_DIR/gen_empty.png" usr/share/plymouth/themes/emerald/debian.png
  fi
  if [ -f usr/share/plymouth/debian-logo.png ]; then
    cp "$ASSETS_DIR/gen_skull_256.png" usr/share/plymouth/debian-logo.png
  fi
  if [ -f etc/os-release ]; then
    cp "$PATCH_ROOT/etc/os-release" etc/os-release
  fi
  find . | cpio -H newc -o 2>/dev/null | zstd -19 -T0 -f -o "$initrd_path"
  cd "$SCRIPT_DIR"
  rm -rf /var/tmp/patch_initrd_installed
done

echo "[*] Setting up Live GRUB configuration and background..."
cp /mnt/iso/live/vmlinuz "$WORKSPACE_DIR/image/live/vmlinuz"
cp "$ASSETS_DIR/gen_grub_16x9.png" "$WORKSPACE_DIR/image/boot/grub/splash.png"

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

echo "[*] Unmounting source V12 ISO..."
umount /mnt/iso

echo "[*] Packaging patched SquashFS..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building V13 ISO with hybrid bootloader..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="V13"

echo "[*] Cleaning up temporary workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Done! Revenant OS V13 ISO ready at: $ISO_TARGET"
ls -lh "$ISO_TARGET"
