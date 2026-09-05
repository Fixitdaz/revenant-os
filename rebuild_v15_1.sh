#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_rebuild_v15_1"
PATCH_ROOT="/var/tmp/patch_root_v15_1"
ISO_SOURCE="$SCRIPT_DIR/revenant_os_toughbook_v15.iso"
ISO_TARGET="$SCRIPT_DIR/revenant_os_toughbook_v15_1.iso"
ISO_ALIAS="$SCRIPT_DIR/revenant_os_toughbook_v15.1.iso"
CACHE_DIR="/var/tmp/revenant_cache"

echo "[*] Cleaning up previous mounts and temporary directories..."
umount /mnt/iso 2>/dev/null || true
umount "$PATCH_ROOT/proc" 2>/dev/null || true
umount "$PATCH_ROOT/sys" 2>/dev/null || true
umount "$PATCH_ROOT/dev/pts" 2>/dev/null || true
umount "$PATCH_ROOT/dev" 2>/dev/null || true
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"
mkdir -p "$CACHE_DIR"

echo "[*] Mounting V15 source ISO..."
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

echo "[*] Unmounting source V15 ISO..."
umount /mnt/iso

echo "[*] Installing additional GUI, Bluetooth, Network, and System utilities..."
mount --bind /proc "$PATCH_ROOT/proc"
mount --bind /sys "$PATCH_ROOT/sys"
mount --bind /dev "$PATCH_ROOT/dev"
mount --bind /dev/pts "$PATCH_ROOT/dev/pts"
cp /etc/resolv.conf "$PATCH_ROOT/etc/resolv.conf"

export DEBIAN_FRONTEND=noninteractive
echo "wireshark-common wireshark-common/install-setuid boolean true" | chroot "$PATCH_ROOT" debconf-set-selections

rm -f "$PATCH_ROOT/var/lib/apt/lists/lock" "$PATCH_ROOT/var/cache/apt/archives/lock" "$PATCH_ROOT/var/lib/dpkg/lock*" 2>/dev/null || true

chroot "$PATCH_ROOT" apt-get update
chroot "$PATCH_ROOT" apt-get install -y --no-install-recommends \
  blueman \
  geany \
  flameshot \
  hardinfo \
  doublecmd-gtk \
  qalculate-gtk \
  wavemon \
  wireshark \
  baobab

chroot "$PATCH_ROOT" apt-get clean
rm -rf "$PATCH_ROOT/var/lib/apt/lists/*"

umount -l "$PATCH_ROOT/dev/pts" 2>/dev/null || true
umount -l "$PATCH_ROOT/dev" 2>/dev/null || true
umount -l "$PATCH_ROOT/sys" 2>/dev/null || true
umount -l "$PATCH_ROOT/proc" 2>/dev/null || true

echo "[*] Verifying llama-server and Qwen2.5-Coder model..."
mkdir -p "$PATCH_ROOT/opt/llama.cpp" "$PATCH_ROOT/opt/models"
if [ ! -f "$PATCH_ROOT/opt/llama.cpp/llama-server" ]; then
  if [ -f "$CACHE_DIR/llama-server" ]; then
    cp "$CACHE_DIR/llama-server" "$PATCH_ROOT/opt/llama.cpp/llama-server"
  fi
fi
chmod +x "$PATCH_ROOT/opt/llama.cpp/llama-server" 2>/dev/null || true

if [ ! -f "$PATCH_ROOT/opt/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" ]; then
  if [ -f "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" ]; then
    cp "$CACHE_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" "$PATCH_ROOT/opt/models/"
  fi
fi

echo "[*] Ensuring systemd services are properly enabled..."
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

mkdir -p "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/llama-server.service "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants/llama-server.service"
ln -sf /etc/systemd/system/openviking.service "$PATCH_ROOT/etc/systemd/system/multi-user.target.wants/openviking.service"

echo "[*] Ensuring live environment sudoers and default passwords..."
echo "user:revenant" | chpasswd -R "$PATCH_ROOT" 2>/dev/null || true
echo "revenant:revenant" | chpasswd -R "$PATCH_ROOT" 2>/dev/null || true
echo "root:revenant" | chpasswd -R "$PATCH_ROOT" 2>/dev/null || true

mkdir -p "$PATCH_ROOT/etc/sudoers.d"
echo "user ALL=(ALL) NOPASSWD: ALL" > "$PATCH_ROOT/etc/sudoers.d/live-user"
echo "revenant ALL=(ALL) NOPASSWD: ALL" >> "$PATCH_ROOT/etc/sudoers.d/live-user"
chmod 0440 "$PATCH_ROOT/etc/sudoers.d/live-user"

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
echo "=== Revenant OS V15.1 Installation Started ===" > "$LOG"
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

echo "75"; echo "# Setting up user account and credentials..."
chroot /mnt/target groupadd -f sudo
chroot /mnt/target groupadd -f plugdev
chroot /mnt/target groupadd -f netdev
chroot /mnt/target groupadd -f wireshark 2>/dev/null || true

if chroot /mnt/target id "$NEW_USER" &>/dev/null; then
  chroot /mnt/target usermod -s /usr/bin/fish -aG sudo,adm,audio,video,netdev,plugdev,dialout,wireshark "$NEW_USER" >> "$LOG" 2>&1 || true
else
  chroot /mnt/target useradd -m -s /usr/bin/fish -G sudo,adm,audio,video,netdev,plugdev,dialout,wireshark "$NEW_USER" >> "$LOG" 2>&1 || true
fi

echo "$NEW_USER:$NEW_PASS" | chroot /mnt/target chpasswd >> "$LOG" 2>&1 || true
echo "root:$NEW_PASS" | chroot /mnt/target chpasswd >> "$LOG" 2>&1 || true

mkdir -p /mnt/target/etc/sudoers.d
echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" > "/mnt/target/etc/sudoers.d/99-$NEW_USER"
chmod 0440 "/mnt/target/etc/sudoers.d/99-$NEW_USER"
sed -i 's/^# *%sudo/%sudo/' /mnt/target/etc/sudoers 2>/dev/null || true

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
if [ -f /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools ]; then
  rm -f /mnt/target/usr/sbin/update-initramfs
  mv /mnt/target/usr/sbin/update-initramfs.orig.initramfs-tools /mnt/target/usr/sbin/update-initramfs
fi

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

menuentry "Revenant OS V15.1 - Agentic Linux" --class debian --class gnu-linux --class gnu --class os {
    load_video
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $UUID
    linux /boot/$VMLINUZ root=UUID=$UUID ro quiet splash
    initrd /boot/$INITRD
}

menuentry "Revenant OS V15.1 (Recovery Mode)" --class debian --class gnu-linux --class gnu --class os {
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
umount /mnt/target/dev/pts 2>/dev/null || true
umount /mnt/target/dev 2>/dev/null || true
umount /mnt/target 2>/dev/null || true

echo "100"; echo "# Installation Complete!"
) | zenity --progress --title="Installing Revenant OS V15.1" --text="Starting installation..." --percentage=0 --auto-close

if [ -f "$LOG" ] && grep -iq "Installing for i386-pc platform" "$LOG"; then
  zenity --info --title="Success" \
    --text="<b>Revenant OS V15.1 has been successfully installed to $DRIVE!</b>\n\nYou can now reboot and remove the USB drive."
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

menuentry "Revenant OS V15.1 - Agentic Core (Offline Local LLM)" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Revenant OS V15.1 (Safe Graphics / Failsafe)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}
EOF

echo "[*] Packaging patched SquashFS (xz compression)..."
mksquashfs "$PATCH_ROOT" "$WORKSPACE_DIR/image/live/filesystem.squashfs" -comp xz

echo "[*] Building V15.1 ISO with hybrid bootloader..."
grub-mkrescue -o "$ISO_TARGET" "$WORKSPACE_DIR/image" --product-name="Revenant OS" --product-version="V15.1"
cp -f "$ISO_TARGET" "$ISO_ALIAS"

echo "[*] Cleaning up workspace..."
rm -rf "$WORKSPACE_DIR" "$PATCH_ROOT"

echo "[*] Build Complete! Revenant OS V15.1 ISO ready at: $ISO_TARGET"
ls -lh "$ISO_TARGET" "$ISO_ALIAS"
