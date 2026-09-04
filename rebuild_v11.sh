#!/bin/bash
set -e

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_rebuild"
PATCH_ROOT="/var/tmp/patch_root"
ISO_SOURCE="$SCRIPT_DIR/revenant_os_toughbook_v10.iso"
ISO_TARGET="$SCRIPT_DIR/revenant_os_toughbook_v11.iso"

echo "[*] Cleaning up any previous mounts..."
umount /mnt/iso 2>/dev/null || true
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Mounting V10 ISO to reuse existing system and Vivaldi..."
mkdir -p /mnt/iso
mount -o loop,ro "$ISO_SOURCE" /mnt/iso

echo "[*] Unpacking SquashFS filesystem (takes ~30s)..."
unsquashfs -d "$PATCH_ROOT" /mnt/iso/live/filesystem.squashfs

echo "[*] Injecting native kernel and initrd into /boot..."
mkdir -p "$PATCH_ROOT/boot"
cp /mnt/iso/live/vmlinuz "$PATCH_ROOT/boot/vmlinuz-6.1.0-50-amd64"
cp /mnt/iso/live/initrd.img "$PATCH_ROOT/boot/initrd.img-6.1.0-50-amd64"

echo "[*] Injecting definitive installer script..."
cat << 'INSTALLEREOF' > "$PATCH_ROOT/usr/local/bin/Install_Revenant_OS.sh"
#!/bin/bash
export LC_ALL=C

if [ "$EUID" -ne 0 ]; then
  zenity --error --title="Permission Denied" --text="Please run as root!\nOpen terminal and run: sudo /usr/local/bin/Install_Revenant_OS.sh"
  exit 1
fi

NEW_USER=$(zenity --entry --title="User Setup" --text="Enter your desired username:" --entry-text="revenant")
if [ -z "$NEW_USER" ]; then exit 0; fi

NEW_PASS=$(zenity --password --title="User Setup" --text="Enter password for user '$NEW_USER':")
if [ -z "$NEW_PASS" ]; then exit 0; fi

CONFIRM_PASS=$(zenity --password --title="User Setup" --text="Confirm password for user '$NEW_USER':")
if [ "$NEW_PASS" != "$CONFIRM_PASS" ]; then
  zenity --error --title="Password Mismatch" --text="Passwords do not match. Installation cancelled."
  exit 1
fi

NEW_HOST=$(zenity --entry --title="Computer Setup" --text="Enter a name for this computer:" --entry-text="revenant-pc")
if [ -z "$NEW_HOST" ]; then exit 0; fi

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
echo "=== Revenant OS Installation Started ===" > "$LOG"
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

echo "75"; echo "# Setting up user account and configuration..."
if chroot /mnt/target id "$NEW_USER" &>/dev/null; then
  chroot /mnt/target usermod -s /usr/bin/fish "$NEW_USER" >> "$LOG" 2>&1 || true
  echo "$NEW_USER:$NEW_PASS" | chroot /mnt/target chpasswd >> "$LOG" 2>&1 || true
else
  chroot /mnt/target useradd -m -s /usr/bin/fish -G sudo,audio,video,netdev,plugdev "$NEW_USER" >> "$LOG" 2>&1 || true
  echo "$NEW_USER:$NEW_PASS" | chroot /mnt/target chpasswd >> "$LOG" 2>&1 || true
fi
echo "root:$NEW_PASS" | chroot /mnt/target chpasswd >> "$LOG" 2>&1 || true

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

mkdir -p /mnt/target/etc/lightdm/lightdm.conf.d
cat << LIGHTDMCONF > /mnt/target/etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=$NEW_USER
autologin-user-timeout=0
user-session=xfce
LIGHTDMCONF

# Remove live-user configs from target
rm -f /mnt/target/etc/sudoers.d/live-user
rm -f /mnt/target/etc/skel/Desktop/Install*.desktop
rm -f "/mnt/target/home/$NEW_USER/Desktop/Install"*.desktop 2>/dev/null || true
rm -f /mnt/target/home/user/Desktop/Install*.desktop 2>/dev/null || true

echo "80"; echo "# Generating fstab..."
UUID=$(blkid -s UUID -o value "$TARGET_PART")
cat << FSTABEOF > /mnt/target/etc/fstab
UUID=$UUID /               ext4    errors=remount-ro,noatime 0       1
tmpfs          /tmp            tmpfs   defaults,nosuid,nodev   0       0
FSTABEOF

echo "85"; echo "# Configuring native kernel and system bootloader..."
# Un-divert update-initramfs if live-tools diverted it
if [ -f /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools ]; then
  rm -f /mnt/target/usr/sbin/update-initramfs
  mv /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools /mnt/target/usr/sbin/update-initramfs
fi

# Ensure /boot has kernel files; fallback to live media if empty
if ! compgen -G "/mnt/target/boot/vmlinuz-*" > /dev/null; then
  for med in /run/live/medium /lib/live/mount/medium /cdrom; do
    if [ -f "$med/live/vmlinuz" ]; then
      cp "$med/live/vmlinuz" /mnt/target/boot/vmlinuz-custom >> "$LOG" 2>&1 || true
      cp "$med/live/initrd.img" /mnt/target/boot/initrd.img-custom >> "$LOG" 2>&1 || true
      break
    fi
  done
fi

# Purge live packages on target so system boots natively
chroot /mnt/target apt-get purge -y live-boot live-boot-doc live-config live-config-doc live-config-systemd live-tools >> "$LOG" 2>&1 || true

mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys
mount --bind /run /mnt/target/run

chroot /mnt/target update-initramfs -u -k all >> "$LOG" 2>&1 || true

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

menuentry "Revenant OS - Agentic Linux" --class debian --class gnu-linux --class gnu --class os {
    load_video
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $UUID
    linux /boot/$VMLINUZ root=UUID=$UUID ro quiet splash
    initrd /boot/$INITRD
}

menuentry "Revenant OS (Recovery Mode)" --class debian --class gnu-linux --class gnu --class os {
    load_video
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

umount /mnt/target/run 2>/dev/null || true
umount /mnt/target/sys 2>/dev/null || true
umount /mnt/target/proc 2>/dev/null || true
umount /mnt/target/dev 2>/dev/null || true
umount /mnt/target 2>/dev/null || true

echo "100"; echo "# Installation Complete!"
) | zenity --progress --title="Installing Revenant OS" --text="Starting installation..." --percentage=0 --auto-close

if [ -f "$LOG" ] && grep -iq "Installing for i386-pc platform" "$LOG"; then
  zenity --info --title="Success" \
    --text="<b>Revenant OS has been successfully installed to $DRIVE!</b>\n\nYou can now reboot and remove the USB drive."
else
  zenity --error --title="Error" \
    --text="An error occurred during installation. Check /tmp/revenant_install.log or the target drive."
fi
INSTALLEREOF
chmod +x "$PATCH_ROOT/usr/local/bin/Install_Revenant_OS.sh"

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

echo "[*] Unmounting source V10 ISO..."
umount /mnt/iso

echo "[*] Packaging patched SquashFS (takes ~2-3 mins)..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building V11 ISO..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="V11"

echo "[*] Cleaning up temporary workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Done! V11 ISO ready at: $ISO_TARGET"
