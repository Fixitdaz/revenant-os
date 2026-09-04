import os

script_path = r'd:\fixit\Documents\Custom Agentic AI Linux ISO for Panasonic Toughbook\build_toughbook_iso.sh'
with open(script_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []

for line in lines:
    if 'ISO_NAME="revenant_os_toughbook_v5.iso"' in line:
        new_lines.append('ISO_NAME="revenant_os_toughbook_v6.iso"\n')
        continue

    if 'echo "grub-pc grub-pc/install_devices empty" | debconf-set-selections' in line:
        new_lines.append('echo "grub-pc grub-pc/install_devices multiselect " | debconf-set-selections\n')
        continue
        
    if 'grub-pc grub-efi-amd64 \\' in line:
        continue # Remove this line which caused the conflict

    if '# (Packages are now fully installed in the chroot so Calamares does not need to apt-get them)' in line:
        new_lines.append('    cd /var/cache/apt/archives && apt-get download grub-pc grub-efi-amd64 grub-pc-bin grub-efi-amd64-bin\n')
        continue

    new_lines.append(line)

with open(script_path, 'w', encoding='utf-8', newline='\n') as f:
    f.writelines(new_lines)
