import os

script_path = r'd:\fixit\Documents\Custom Agentic AI Linux ISO for Panasonic Toughbook\build_toughbook_iso.sh'
with open(script_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
skip = False

for i, line in enumerate(lines):
    if 'ISO_NAME="revenant_os_toughbook_v6.iso"' in line:
        new_lines.append('ISO_NAME="revenant_os_toughbook_v7.iso"\n')
        continue

    # Replace calamares with zenity
    if 'fish neofetch calamares calamares-settings-debian feh \\' in line:
        new_lines.append('    fish neofetch feh zenity parted rsync dialog \\\n')
        continue
        
    # Replace grub line to only install grub-pc, since CF-52 is Legacy BIOS
    if 'firmware-linux-free grub-pc-bin grub-efi-amd64-bin os-prober efibootmgr \\' in line:
        new_lines.append('    firmware-linux-free grub-pc os-prober \\')
        continue

    # Remove the caching workaround
    if 'cd /var/cache/apt/archives && apt-get download grub-pc' in line:
        continue
    if 'apt-get update' in line and lines[i+1].find('cd /var/cache/apt/archives') != -1:
        continue

    # Inject default wallpaper XML properly
    if '# Create XFCE wallpaper autostart' in line:
        new_lines.append("""
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
""")
        # Skip the old bad autostart
        skip = True
        continue
        
    if skip and 'XFCEEOF' in line:
        skip = False
        continue
    if skip:
        continue

    if 'EOF' in line and lines[i-1].find('rm /setup_chroot.sh') != -1:
        new_lines.append(line)
        # Inject our installer script creation
        new_lines.append("""
# Create custom bespoke installer
mkdir -p "$CHROOT_DIR/etc/skel/Desktop"
cat << 'INSTALLEREOF' > "$CHROOT_DIR/etc/skel/Desktop/Install_Revenant_OS.sh"
#!/bin/bash
export LC_ALL=C
if [ "\\$EUID" -ne 0 ]; then
  zenity --error --text="Please run as root! Open terminal and run: sudo ./Install_Revenant_OS.sh"
  exit 1
fi

DRIVES=\\$(lsblk -d -n -o NAME,SIZE | grep -E "sd|nvme|vd" | awk '{print "/dev/"\\$1" ("\\$2")"}')
DRIVE=\\$(zenity --list --title="Select Target Drive" --text="WARNING: ALL DATA WILL BE ERASED!\\nSelect the drive to install Revenant OS:" --column="Available Drives" \\$DRIVES 2>/dev/null)

if [ -z "\\$DRIVE" ]; then
    exit 0
fi

DRIVE=\\$(echo "\\$DRIVE" | awk '{print \\$1}')

zenity --question --title="Confirm Installation" --text="Are you absolutely sure you want to install to \\$DRIVE?\\n\\nTHIS WILL ERASE EVERYTHING ON \\$DRIVE!" || exit 0

(
echo "10"; echo "# Formatting drive \\$DRIVE..."
parted -s "\\$DRIVE" mklabel msdos
parted -s -a optimal "\\$DRIVE" mkpart primary ext4 0% 100%
parted -s "\\$DRIVE" set 1 boot on
mkfs.ext4 -F "\\${DRIVE}1"

echo "30"; echo "# Mounting drive..."
mkdir -p /mnt/target
mount "\\${DRIVE}1" /mnt/target

echo "40"; echo "# Copying system files (this will take a few minutes)..."
rsync -aAX --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/live/*","/cdrom/*"} / /mnt/target/

echo "80"; echo "# Generating fstab..."
UUID=\\$(blkid -s UUID -o value "\\${DRIVE}1")
echo "UUID=\\$UUID / ext4 defaults,noatime 0 1" > /mnt/target/etc/fstab

echo "90"; echo "# Configuring bootloader..."
mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys

chroot /mnt/target bash -c "update-initramfs -u"
chroot /mnt/target grub-install "\\$DRIVE"
chroot /mnt/target update-grub

echo "95"; echo "# Cleaning up..."
umount /mnt/target/sys
umount /mnt/target/proc
umount /mnt/target/dev
umount /mnt/target

echo "100"; echo "# Installation Complete!"
) | zenity --progress --title="Installing Revenant OS" --text="Starting installation..." --percentage=0 --auto-close

if [ \\${PIPESTATUS[0]} -eq 0 ]; then
    zenity --info --title="Success" --text="Revenant OS has been successfully installed!\\n\\nYou can now reboot and remove the USB drive."
else
    zenity --error --title="Error" --text="An error occurred during installation."
fi
INSTALLEREOF
chmod +x "$CHROOT_DIR/etc/skel/Desktop/Install_Revenant_OS.sh"
""")
        continue

    new_lines.append(line)

with open(script_path, 'w', encoding='utf-8', newline='\n') as f:
    f.writelines(new_lines)
