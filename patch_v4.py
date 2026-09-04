import os

script_path = r'd:\fixit\Documents\Custom Agentic AI Linux ISO for Panasonic Toughbook\build_toughbook_iso.sh'
with open(script_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
skip_lspci = False

for line in lines:
    if 'ISO_NAME=' in line:
        new_lines.append('ISO_NAME=\"revenant_os_toughbook_v4.iso\"\n')
        continue
    
    if '# 3. Intel/Atheros Wi-Fi cards' in line:
        skip_lspci = True
        continue
    if skip_lspci and 'fi' in line:
        skip_lspci = False
        continue
    if skip_lspci:
        continue
        
    if 'network-manager curl gnupg sudo \\' in line:
        new_lines.append(line)
        new_lines.append('    network-manager-gnome firmware-iwlwifi firmware-atheros firmware-realtek firmware-misc-nonfree firmware-brcm80211 bluetooth bluez bluez-firmware \\\n')
        continue
        
    if '# Install Node.js & OmniRoute' in line:
        new_lines.append('# Install OpenInterpreter and OpenViking for Agentic Core\n')
        new_lines.append('pip3 install --break-system-packages open-interpreter\n\n')
        new_lines.append(line)
        continue
        
    if 'echo "[*] Copying Revenant OS Wallpaper..."' in line:
        new_lines.append('''# Create XFCE wallpaper autostart
mkdir -p "$CHROOT_DIR/etc/xdg/autostart"
cat << 'XFCEEOF' > "$CHROOT_DIR/etc/xdg/autostart/revenant-wallpaper.desktop"
[Desktop Entry]
Type=Application
Name=Revenant Wallpaper
Exec=sh -c 'sleep 2 && xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s /usr/share/backgrounds/revenant_wallpaper.jpg'
Terminal=false
Hidden=false
XFCEEOF

# Create OTA Updater command
cat << 'OTAEOF' > "$CHROOT_DIR/usr/local/bin/revenant-updater"
#!/bin/bash
echo -e "\\033[96m[Revenant OTA Updater]\\033[0m Checking for Agentic Core updates..."
echo "(This will pull from the GitHub repository in the future!)"
echo "System is up to date."
OTAEOF
chmod +x "$CHROOT_DIR/usr/local/bin/revenant-updater"

''')
        new_lines.append(line)
        continue

    new_lines.append(line)

with open(script_path, 'w', encoding='utf-8', newline='\n') as f:
    f.writelines(new_lines)
