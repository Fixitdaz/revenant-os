import os

script_path = r'd:\fixit\Documents\Custom Agentic AI Linux ISO for Panasonic Toughbook\build_toughbook_iso.sh'
with open(script_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []

for line in lines:
    if 'ISO_NAME="revenant_os_toughbook_v4.iso"' in line:
        new_lines.append('ISO_NAME="revenant_os_toughbook_v5.iso"\n')
        continue

    if 'firmware-linux-free grub-pc-bin grub-efi-amd64-bin os-prober efibootmgr \\' in line:
        # Keep it but we will also install grub-pc and grub-efi-amd64 properly later
        new_lines.append(line)
        continue
        
    if 'apt-get install -y \\' in line:
        new_lines.append('# Preseed GRUB so it installs non-interactively\n')
        new_lines.append('echo "grub-pc grub-pc/install_devices empty" | debconf-set-selections\n')
        new_lines.append('echo "grub-pc grub-pc/frontend string Noninteractive" | debconf-set-selections\n')
        new_lines.append(line)
        continue

    if 'network-manager-gnome firmware-iwlwifi' in line:
        new_lines.append(line)
        new_lines.append('    grub-pc grub-efi-amd64 \\\n')
        continue

    if 'cd /var/cache/apt/archives && apt-get download' in line:
        # We don't need to download them if they are already installed in the image
        new_lines.append('    # (Packages are now fully installed in the chroot so Calamares does not need to apt-get them)\n')
        continue

    if 'cp "$SCRIPT_DIR/revenant_wallpaper.jpg" "$CHROOT_DIR/usr/share/backgrounds/revenant_wallpaper.jpg"' in line:
        new_lines.append(line)
        new_lines.append('mkdir -p "$CHROOT_DIR/usr/share/backgrounds/xfce"\n')
        new_lines.append('cp "$SCRIPT_DIR/revenant_wallpaper.jpg" "$CHROOT_DIR/usr/share/backgrounds/xfce/xfce-shapes.svg"\n')
        new_lines.append('cp "$SCRIPT_DIR/revenant_wallpaper.jpg" "$CHROOT_DIR/usr/share/backgrounds/xfce/xfce-stripes.png"\n')
        continue
        
    new_lines.append(line)

with open(script_path, 'w', encoding='utf-8', newline='\n') as f:
    f.writelines(new_lines)
