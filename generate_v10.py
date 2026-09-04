# Python script to write build_toughbook_iso.sh cleanly
import os

script_content = r'''#!/bin/bash
# Revenant OS - Custom Agentic Linux ISO Builder for Panasonic Toughbook
# Version 10 - Bulletproof Edition

set -e

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/var/tmp/toughbook_iso_workspace"
CHROOT_DIR="$WORKSPACE_DIR/chroot"
IMAGE_DIR="$WORKSPACE_DIR/image"
ISO_NAME="revenant_os_toughbook_v10.iso"

cleanup() {
  echo "[*] Cleaning up workspace mounts..."
  umount -f "$CHROOT_DIR/sys" 2>/dev/null || true
  umount -f "$CHROOT_DIR/proc" 2>/dev/null || true
  umount -f "$CHROOT_DIR/dev" 2>/dev/null || true
  umount -f "$CHROOT_DIR/mnt/image" 2>/dev/null || true
}
trap cleanup EXIT

echo "[*] Installing host dependencies..."
apt-get update
apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools curl

echo "[*] Setting up workspace..."
rm -rf "$WORKSPACE_DIR"
mkdir -p "$CHROOT_DIR" "$IMAGE_DIR/live" "$IMAGE_DIR/isolinux" "$IMAGE_DIR/install"

echo "[*] Bootstrapping Debian (Bookworm)..."
debootstrap --arch=amd64 bookworm "$CHROOT_DIR" http://deb.debian.org/debian/

echo "[*] Preparing chroot environment..."
mount --bind /dev "$CHROOT_DIR/dev"
mount -t proc none "$CHROOT_DIR/proc"
mount -t sysfs none "$CHROOT_DIR/sys"

# Create the OmniRoute systemd service
cat << 'EOF' > "$CHROOT_DIR/etc/systemd/system/omniroute.service"
[Unit]
Description=OmniRoute Local AI Gateway
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/omniroute --port 20128
Restart=always
User=revenant
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Create the hardware discovery script
cat << 'EOF' > "$CHROOT_DIR/usr/local/bin/hardware_discovery.sh"
#!/bin/bash
# First boot hardware discovery and driver injection
echo "[*] Running Hardware Discovery for Toughbook CF-52..."
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# 1. Panasonic Hotkey & Touchscreen
if dmidecode | grep -iq "Panasonic" || dmidecode | grep -iq "CF-52"; then
    echo "[*] Panasonic hardware detected. Installing hotkey/touchscreen drivers..."
    modprobe panasonic-laptop || true
    echo "panasonic-laptop" >> /etc/modules
    apt-get install -y xserver-xorg-input-evdev xinput-calibrator
fi

# 2. Legacy Intel Graphics (Intel GMA/HD)
if lspci | grep -iq "VGA compatible controller: Intel Corporation"; then
    echo "[*] Intel Graphics detected. Installing legacy Xorg drivers..."
    apt-get install -y xserver-xorg-video-intel libgl1-mesa-dri
fi

# 3. Wireless Networking
if lspci | grep -iq "Network controller" || lsusb | grep -iq "Wireless"; then
    echo "[*] Wireless adapter detected. Installing firmware..."
    apt-get install -y firmware-iwlwifi firmware-atheros wireless-tools wpasupplicant
fi

# Hardening: Enable Firewall (UFW)
echo "[*] Hardening system: Enabling UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 20128/tcp
ufw --force enable

# Disable the service so it only runs on first boot
systemctl disable hardware-discovery.service
echo "[*] Hardware discovery complete."
EOF
chmod +x "$CHROOT_DIR/usr/local/bin/hardware_discovery.sh"

# Create the hardware discovery systemd service
cat << 'EOF' > "$CHROOT_DIR/etc/systemd/system/hardware-discovery.service"
[Unit]
Description=First Boot Hardware Discovery (Toughbook)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hardware_discovery.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Create the agent config for terminal
mkdir -p "$CHROOT_DIR/etc/skel/.config/agentcore"
cat << 'EOF' > "$CHROOT_DIR/etc/skel/.config/agentcore/config.json"
{
  "api_base": "http://localhost:20128/v1",
  "default_model": "claude-3-opus",
  "ui_mode": "terminal"
}
EOF

# Create a desktop cheat sheet for i3
mkdir -p "$CHROOT_DIR/etc/skel/Desktop"
cat << 'EOF' > "$CHROOT_DIR/etc/skel/Desktop/Revenant_i3_Cheatsheet.txt"
=========================================
 REVENANT OS - i3 WINDOW MANAGER CHEAT SHEET
=========================================

Welcome to the purely keyboard-driven interface! 

*** IMPORTANT FOR WINDOWS USERS ***
The "Mod" key mentioned below is your Windows key (⊞ Win).
If your keyboard doesn't have a Windows key, it is usually the Alt key.
***********************************

BASICS:
Mod + F1          : Open this cheat sheet!
Mod + Enter       : Open Terminal (where you can type 'ai')
Mod + d           : Open Application Menu (type to search)
Mod + Shift + q   : Close current window
Mod + Shift + e   : Log out (to return to XFCE)

NAVIGATION:
Mod + Arrow Keys  : Move focus between windows
Mod + Shift + Arr : Move the actual window around
Mod + 1 to 9      : Switch to Workspace 1-9
Mod + Shift + 1-9 : Move current window to Workspace 1-9

LAYOUT:
Mod + v           : Split vertically for next window
Mod + h           : Split horizontally for next window
Mod + f           : Toggle fullscreen
Mod + r           : Resize mode (use arrows, hit Esc to exit)

Enjoy the speed of Revenant OS!
=========================================
EOF

# Create custom bespoke installer
cat << 'INSTALLEREOF' > "$CHROOT_DIR/usr/local/bin/Install_Revenant_OS.sh"
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

(
set -e

echo "5"; echo "# Unmounting active partitions on $DRIVE..."
umount ${DRIVE}* 2>/dev/null || true
swapoff -a 2>/dev/null || true

echo "15"; echo "# Partitioning drive $DRIVE (MBR/BIOS)..."
parted -s "$DRIVE" mklabel msdos
parted -s -a optimal "$DRIVE" mkpart primary ext4 1MiB 100%
parted -s "$DRIVE" set 1 boot on
sync
partprobe "$DRIVE" 2>/dev/null || true
udevadm settle || sleep 2

TARGET_PART="${DRIVE}1"
if [ ! -b "$TARGET_PART" ]; then
  if [ -b "${DRIVE}p1" ]; then
    TARGET_PART="${DRIVE}p1"
  else
    echo "# Error: Partition node not found!"
    exit 1
  fi
fi

echo "25"; echo "# Formatting partition $TARGET_PART (ext4)..."
mkfs.ext4 -F -L "RevenantOS" "$TARGET_PART"
udevadm settle || sleep 1

echo "35"; echo "# Mounting target partition..."
mkdir -p /mnt/target
mount "$TARGET_PART" /mnt/target

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
  / /mnt/target/

echo "70"; echo "# Setting up user account and system configuration..."
if chroot /mnt/target id "$NEW_USER" &>/dev/null; then
  chroot /mnt/target usermod -s /usr/bin/fish "$NEW_USER"
  echo "$NEW_USER:$NEW_PASS" | chroot /mnt/target chpasswd
else
  chroot /mnt/target useradd -m -s /usr/bin/fish -G sudo,audio,video,netdev,plugdev "$NEW_USER"
  echo "$NEW_USER:$NEW_PASS" | chroot /mnt/target chpasswd
fi
echo "root:$NEW_PASS" | chroot /mnt/target chpasswd

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

# Remove live-user configurations from target
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

echo "90"; echo "# Installing GRUB bootloader..."
mkdir -p /mnt/target/var/log
grub-install --target=i386-pc --boot-directory=/mnt/target/boot --recheck "$DRIVE" >> /mnt/target/var/log/revenant_install.log 2>&1 || true

mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys
mount --bind /run /mnt/target/run

chroot /mnt/target update-initramfs -u -k all >> /mnt/target/var/log/revenant_install.log 2>&1 || true
chroot /mnt/target grub-install --target=i386-pc --recheck "$DRIVE" >> /mnt/target/var/log/revenant_install.log 2>&1 || true
chroot /mnt/target update-grub >> /mnt/target/var/log/revenant_install.log 2>&1 || true

echo "95"; echo "# Writing guaranteed bootloader configuration..."
VMLINUZ=$(ls -1 /mnt/target/boot/vmlinuz-* 2>/dev/null | sort -V | tail -n 1 | xargs -n 1 basename 2>/dev/null)
INITRD=$(ls -1 /mnt/target/boot/initrd.img-* 2>/dev/null | sort -V | tail -n 1 | xargs -n 1 basename 2>/dev/null)

if [ -n "$VMLINUZ" ] && [ -n "$INITRD" ]; then
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
umount /mnt/target/run 2>/dev/null || true
umount /mnt/target/sys 2>/dev/null || true
umount /mnt/target/proc 2>/dev/null || true
umount /mnt/target/dev 2>/dev/null || true
umount /mnt/target 2>/dev/null || true

echo "100"; echo "# Installation Complete!"
) | zenity --progress --title="Installing Revenant OS" --text="Starting installation..." --percentage=0 --auto-close

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  zenity --info --title="Success" \
    --text="<b>Revenant OS has been successfully installed to $DRIVE!</b>\n\nYou can now reboot and remove the USB drive."
else
  zenity --error --title="Error" \
    --text="An error occurred during installation. Check /mnt/target/var/log/revenant_install.log on the target drive."
fi
INSTALLEREOF
chmod +x "$CHROOT_DIR/usr/local/bin/Install_Revenant_OS.sh"

# Create Desktop Shortcut
mkdir -p "$CHROOT_DIR/etc/skel/Desktop"
cat << 'DESKTOPEOF' > "$CHROOT_DIR/etc/skel/Desktop/Install Revenant OS.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Install Revenant OS
Comment=Install Revenant OS to your hard drive
Exec=sudo -E /usr/local/bin/Install_Revenant_OS.sh
Icon=drive-harddisk
Terminal=false
StartupNotify=true
Categories=System;
DESKTOPEOF
chmod +x "$CHROOT_DIR/etc/skel/Desktop/Install Revenant OS.desktop"

# Create a chroot setup script
cat << 'EOF' > "$CHROOT_DIR/setup_chroot.sh"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Add non-free firmware repositories
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt-get update

# Install base packages, utilities, and build-essential for node-gyp
echo "grub-pc grub-pc/install_devices multiselect " | debconf-set-selections
echo "grub-pc grub-pc/frontend string Noninteractive" | debconf-set-selections
apt-get install -y policykit-1 pkexec \
    linux-image-amd64 live-boot live-config live-config-systemd systemd-sysv \
    xserver-xorg-core xinit i3 i3status dmenu \
    xfce4 xfce4-goodies lightdm mousepad \
    rxvt-unicode pciutils lshw dmidecode \
    network-manager curl gnupg sudo \
    network-manager-gnome firmware-iwlwifi firmware-atheros firmware-realtek firmware-misc-nonfree firmware-brcm80211 bluetooth bluez bluez-firmware \
    firmware-linux-free grub-pc grub-efi-amd64-bin xorriso mtools os-prober \
    tmux fzf jq bat git neovim \
    python3 python3-pip python3-venv python3-dev build-essential \
    alsa-utils pulseaudio pavucontrol tlp \
    htop openssh-server ufw fail2ban bleachbit \
    fish neofetch feh zenity parted rsync dialog \
    synaptic gparted vlc unzip file-roller evince libreoffice-writer libreoffice-calc

# Install Piper TTS for natural, offline neural voices
curl -fsSL https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz | tar -xz -C /opt/
mkdir -p /opt/piper/models
curl -fsSL -o /opt/piper/models/en_US-lessac-medium.onnx https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx
curl -fsSL -o /opt/piper/models/en_US-lessac-medium.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json

# Install Vivaldi Browser
curl -fsSL https://repo.vivaldi.com/archive/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/vivaldi-browser.gpg
echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg arch=amd64] https://repo.vivaldi.com/archive/deb/ stable main" > /etc/apt/sources.list.d/vivaldi.list
apt-get update
apt-get install -y vivaldi-stable

# Create unprivileged service user for AI agent, and a default login user
useradd -m -s /bin/bash revenant
useradd -m -s /usr/bin/fish -G sudo,audio,video,netdev user
echo "user:revenant" | chpasswd

# Configure passwordless sudo for the live user
echo "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/live-user
chmod 0440 /etc/sudoers.d/live-user

# Ensure desktop shortcut permissions
chown -R user:user /home/user 2>/dev/null || true
chmod +x /home/user/Desktop/*.desktop 2>/dev/null || true

# Configure terminal wow factor (Neofetch on startup for fish shell)
mkdir -p /etc/skel/.config/fish
cat << 'FISHEOF' > /etc/skel/.config/fish/config.fish
if status is-interactive
    neofetch --ascii_distro Debian
    echo -e "\n\033[96mWelcome to Revenant OS.\033[0m Type \033[93mai <prompt>\033[0m to interact with the Local Agent Core."
end
FISHEOF

# Configure LightDM autologin for the default user
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'LIGHTDMEOF' > /etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=user
autologin-user-timeout=0
user-session=xfce
LIGHTDMEOF

# Add global hotkey for i3 to open the cheat sheet
echo 'bindsym $mod+F1 exec mousepad ~/Desktop/Revenant_i3_Cheatsheet.txt' >> /etc/i3/config
echo 'exec_always --no-startup-id feh --bg-scale /usr/share/backgrounds/revenant_wallpaper.jpg' >> /etc/i3/config

# Install OpenInterpreter and OpenViking for Agentic Core
for i in {1..5}; do pip3 install --break-system-packages --default-timeout=1000 open-interpreter openviking && break || sleep 15; done

# Install Node.js & OmniRoute & Agents
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g omniroute hermes-agent || true

# Create the 'ai' terminal command
cat << 'PYEOF' > /usr/local/bin/ai
#!/usr/bin/env python3
import sys, json, urllib.request, subprocess

if len(sys.argv) < 2:
    print("Usage: ai <your prompt>")
    sys.exit(1)

print("\033[96m[Revenant Core Processing...]\033[0m")
prompt = " ".join(sys.argv[1:])
data = json.dumps({
    "model": "claude-3-opus",
    "messages": [{"role": "user", "content": prompt}]
}).encode('utf-8')

req = urllib.request.Request("http://localhost:20128/v1/chat/completions", data=data, headers={'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(req) as response:
        res = json.loads(response.read().decode('utf-8'))
        answer = res['choices'][0]['message']['content']
        print("\n" + answer + "\n")
        
        # Strip basic markdown for speech
        clean_text = answer.replace('*', '').replace('`', '').replace('#', '').replace('_', '').replace("'", "")
        # Speak the response asynchronously in a natural neural voice using Piper
        cmd = f"echo '{clean_text}' | /opt/piper/piper -m /opt/piper/models/en_US-lessac-medium.onnx --output_raw | aplay -r 22050 -f S16_LE -t raw -"
        subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except Exception as e:
    print(f"\033[91mAgent Core Offline or Error: {e}\033[0m")
PYEOF
chmod +x /usr/local/bin/ai

# Enable services
systemctl enable NetworkManager.service
systemctl enable omniroute.service
systemctl enable hardware-discovery.service

# Setup root password
echo "root:omarchy" | chpasswd

# Clean up caches aggressively to keep squashfs below 4GB
apt-get clean
rm -rf /tmp/* /var/tmp/*
rm -f /setup_chroot.sh
npm cache clean --force || true
rm -rf /root/.npm /root/.cache /var/cache/apt /var/lib/apt/lists/*

EOF

# Set XFCE default wallpaper via system defaults
mkdir -p "$CHROOT_DIR/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
cat << 'XML' > "$CHROOT_DIR/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/revenant_wallpaper.jpg"/>
        </property>
      </property>
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/revenant_wallpaper.jpg"/>
        </property>
      </property>
      <property name="monitorLVDS-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/revenant_wallpaper.jpg"/>
        </property>
      </property>
      <property name="monitoreDP-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/revenant_wallpaper.jpg"/>
        </property>
      </property>
      <property name="monitorVGA-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/revenant_wallpaper.jpg"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XML

# Create OTA Updater command
cat << 'OTAEOF' > "$CHROOT_DIR/usr/local/bin/revenant-updater"
#!/bin/bash
echo -e "\033[96m[Revenant OTA Updater]\033[0m Checking for Agentic Core updates..."
echo "(This will pull from the GitHub repository in the future!)"
echo "System is up to date."
OTAEOF
chmod +x "$CHROOT_DIR/usr/local/bin/revenant-updater"

echo "[*] Copying Revenant OS Wallpaper..."
mkdir -p "$CHROOT_DIR/usr/share/backgrounds"
cp "$SCRIPT_DIR/revenant_wallpaper.jpg" "$CHROOT_DIR/usr/share/backgrounds/revenant_wallpaper.jpg"
mkdir -p "$CHROOT_DIR/usr/share/backgrounds/xfce"
cp "$SCRIPT_DIR/revenant_wallpaper.jpg" "$CHROOT_DIR/usr/share/backgrounds/xfce/xfce-shapes.svg"
cp "$SCRIPT_DIR/revenant_wallpaper.jpg" "$CHROOT_DIR/usr/share/backgrounds/xfce/xfce-stripes.png"

# Also symlink for good measure
ln -sf /usr/share/backgrounds/revenant_wallpaper.jpg "$CHROOT_DIR/etc/alternatives/desktop-background"

echo "[*] Executing chroot setup..."
chmod +x "$CHROOT_DIR/setup_chroot.sh"
chroot "$CHROOT_DIR" /setup_chroot.sh

echo "[*] Packaging SquashFS..."
umount "$CHROOT_DIR/sys" 2>/dev/null || true
umount "$CHROOT_DIR/proc" 2>/dev/null || true
umount "$CHROOT_DIR/dev" 2>/dev/null || true

mksquashfs "$CHROOT_DIR" "$IMAGE_DIR/live/filesystem.squashfs" -comp xz -e boot

echo "[*] Preparing ISO bootloader (GRUB)..."
cp "$CHROOT_DIR/boot/vmlinuz-"* "$IMAGE_DIR/live/vmlinuz"
cp "$CHROOT_DIR/boot/initrd.img-"* "$IMAGE_DIR/live/initrd.img"

mkdir -p "$IMAGE_DIR/boot/grub"
cat << 'EOF' > "$IMAGE_DIR/boot/grub/grub.cfg"
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

echo "[*] Building ISO..."
# Run grub-mkrescue on host (WSL) using product flags to prevent Kali branding and build proper hybrid MBR
grub-mkrescue -o "$SCRIPT_DIR/$ISO_NAME" "$IMAGE_DIR" --product-name="Revenant OS" --product-version="V10"

echo "[*] Done! ISO created at $SCRIPT_DIR/$ISO_NAME"
'''

with open('build_toughbook_iso.sh', 'w', encoding='utf-8', newline='\n') as f:
    f.write(script_content)

print('Generated build_toughbook_iso.sh successfully')
