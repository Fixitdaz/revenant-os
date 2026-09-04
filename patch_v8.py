import os

script_path = "build_toughbook_iso.sh"

with open(script_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add packages to pip install
content = content.replace(
    'pip3 install --break-system-packages open-interpreter',
    'pip3 install --break-system-packages open-interpreter openviking'
)

# 2. Add packages to npm install
content = content.replace(
    'npm install -g omniroute',
    'npm install -g omniroute hermes-agent || true'
)

# 3. Modify the bespoke installer script to add user prompts and fix GRUB
old_installer = """cat << 'INSTALLEREOF' > "$CHROOT_DIR/etc/skel/Desktop/Install_Revenant_OS.sh"
#!/bin/bash
export LC_ALL=C
if [ "$EUID" -ne 0 ]; then
  zenity --error --text="Please run as root! Open terminal and run: sudo ./Install_Revenant_OS.sh"
  exit 1
fi

DRIVES=$(lsblk -d -n -o NAME,SIZE | grep -E "sd|nvme|vd" | awk '{print "/dev/"$1" ("$2")"}')
DRIVE=$(zenity --list --title="Select Target Drive" --text="WARNING: ALL DATA WILL BE ERASED!\\nSelect the drive to install Revenant OS:" --column="Available Drives" $DRIVES 2>/dev/null)

if [ -z "$DRIVE" ]; then
    exit 0
fi

DRIVE=$(echo "$DRIVE" | awk '{print $1}')

zenity --question --title="Confirm Installation" --text="Are you absolutely sure you want to install to $DRIVE?\\n\\nTHIS WILL ERASE EVERYTHING ON $DRIVE!" || exit 0

(
echo "10"; echo "# Formatting drive $DRIVE..."
parted -s "$DRIVE" mklabel msdos
parted -s -a optimal "$DRIVE" mkpart primary ext4 0% 100%
parted -s "$DRIVE" set 1 boot on
mkfs.ext4 -F "${DRIVE}1"

echo "30"; echo "# Mounting drive..."
mkdir -p /mnt/target
mount "${DRIVE}1" /mnt/target

echo "40"; echo "# Copying system files (this will take a few minutes)..."
rsync -aAX --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/live/*","/cdrom/*"} / /mnt/target/

echo "80"; echo "# Generating fstab..."
UUID=$(blkid -s UUID -o value "${DRIVE}1")
echo "UUID=$UUID / ext4 defaults,noatime 0 1" > /mnt/target/etc/fstab

echo "90"; echo "# Configuring bootloader..."
mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys

chroot /mnt/target bash -c "update-initramfs -u"
chroot /mnt/target grub-install "$DRIVE"
chroot /mnt/target update-grub

echo "95"; echo "# Cleaning up..."
umount /mnt/target/sys
umount /mnt/target/proc
umount /mnt/target/dev
umount /mnt/target

echo "100"; echo "# Installation Complete!"
) | zenity --progress --title="Installing Revenant OS" --text="Starting installation..." --percentage=0 --auto-close

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    zenity --info --title="Success" --text="Revenant OS has been successfully installed!\\n\\nYou can now reboot and remove the USB drive."
else
    zenity --error --title="Error" --text="An error occurred during installation."
fi
INSTALLEREOF
chmod +x "$CHROOT_DIR/etc/skel/Desktop/Install_Revenant_OS.sh"
"""

new_installer = """cat << 'INSTALLEREOF' > "$CHROOT_DIR/usr/local/bin/Install_Revenant_OS.sh"
#!/bin/bash
export LC_ALL=C
if [ "$EUID" -ne 0 ]; then
  zenity --error --text="Please run as root! Open terminal and run: sudo ./Install_Revenant_OS.sh"
  exit 1
fi

NEW_USER=$(zenity --entry --title="User Setup" --text="Enter your desired username:" --entry-text="revenant")
if [ -z "$NEW_USER" ]; then exit 0; fi

NEW_PASS=$(zenity --password --title="User Setup" --text="Enter your desired password:")
if [ -z "$NEW_PASS" ]; then exit 0; fi

NEW_HOST=$(zenity --entry --title="Computer Setup" --text="Enter a name for this computer:" --entry-text="revenant-pc")
if [ -z "$NEW_HOST" ]; then exit 0; fi

DRIVES=$(lsblk -d -n -o NAME,SIZE | grep -E "sd|nvme|vd" | awk '{print "/dev/"$1" ("$2")"}')
DRIVE=$(zenity --list --title="Select Target Drive" --text="WARNING: ALL DATA WILL BE ERASED!\\n(Make sure to click the drive to highlight it)\\nSelect the drive to install Revenant OS:" --column="Available Drives" $DRIVES 2>/dev/null)

if [ -z "$DRIVE" ]; then
    exit 0
fi

DRIVE=$(echo "$DRIVE" | awk '{print $1}')

zenity --question --title="Confirm Installation" --text="Are you absolutely sure you want to install to $DRIVE?\\n\\nTHIS WILL ERASE EVERYTHING ON $DRIVE!" || exit 0

(
echo "10"; echo "# Formatting drive $DRIVE..."
parted -s "$DRIVE" mklabel msdos
parted -s -a optimal "$DRIVE" mkpart primary ext4 0% 100%
parted -s "$DRIVE" set 1 boot on
mkfs.ext4 -F "${DRIVE}1"

echo "30"; echo "# Mounting drive..."
mkdir -p /mnt/target
mount "${DRIVE}1" /mnt/target

echo "40"; echo "# Copying system files (this will take a few minutes)..."
rsync -aAX --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/live/*","/cdrom/*"} / /mnt/target/

echo "70"; echo "# Setting up user and hostname..."
chroot /mnt/target bash -c "useradd -m -s /usr/bin/fish -G sudo,audio,video,netdev $NEW_USER"
echo "$NEW_USER:$NEW_PASS" | chroot /mnt/target chpasswd
echo "$NEW_HOST" > /mnt/target/etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\\t$NEW_HOST/g" /mnt/target/etc/hosts
sed -i "s/autologin-user=user/autologin-user=$NEW_USER/g" /mnt/target/etc/lightdm/lightdm.conf.d/50-autologin.conf

echo "80"; echo "# Generating fstab..."
UUID=$(blkid -s UUID -o value "${DRIVE}1")
echo "UUID=$UUID / ext4 defaults,noatime 0 1" > /mnt/target/etc/fstab

echo "90"; echo "# Configuring bootloader..."
mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys
mount --bind /run /mnt/target/run

chroot /mnt/target bash -c "update-initramfs -u" > /mnt/target/var/log/revenant_install.log 2>&1
chroot /mnt/target grub-install "$DRIVE" >> /mnt/target/var/log/revenant_install.log 2>&1
chroot /mnt/target update-grub >> /mnt/target/var/log/revenant_install.log 2>&1

echo "95"; echo "# Cleaning up..."
umount /mnt/target/run
umount /mnt/target/sys
umount /mnt/target/proc
umount /mnt/target/dev
umount /mnt/target

echo "100"; echo "# Installation Complete!"
) | zenity --progress --title="Installing Revenant OS" --text="Starting installation..." --percentage=0 --auto-close

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    zenity --info --title="Success" --text="Revenant OS has been successfully installed!\\n\\nYou can now reboot and remove the USB drive."
else
    zenity --error --title="Error" --text="An error occurred during installation. Check /var/log/revenant_install.log on the target drive."
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
Comment=Install the OS to your hard drive
Exec=pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY /usr/local/bin/Install_Revenant_OS.sh
Icon=drive-harddisk
Terminal=false
StartupNotify=true
DESKTOPEOF
chmod +x "$CHROOT_DIR/etc/skel/Desktop/Install Revenant OS.desktop"
"""

content = content.replace(old_installer, new_installer)

# 4. Install policykit-1 and pkexec
content = content.replace(
    'apt-get install -y \\',
    'apt-get install -y policykit-1 pkexec \\'
)

# 5. Fix V7 ISO name to V8
content = content.replace(
    'ISO_NAME="revenant_os_toughbook_v7.iso"',
    'ISO_NAME="revenant_os_toughbook_v8.iso"'
)

with open(script_path, 'w', encoding='utf-8', newline='\\n') as f:
    f.write(content)
