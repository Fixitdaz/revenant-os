# Getting Started with Revenant OS

## System Requirements
- **Recommended Hardware**: Panasonic Toughbook CF-52 (Mark 1, 2, 3, 4, 5).
- **Compatible Hardware**: Any x86_64 laptop or workstation with Legacy BIOS (MBR) or UEFI support.
- **Minimum RAM**: 2 GB (4 GB recommended for local LLM routing and browser multitasking).
- **Storage**: 20 GB or larger internal SATA HDD or SSD.
- **Boot Media**: 4 GB or larger USB Flash Drive.

---

## Flashing the USB Drive

### Option A: Using Rufus (Windows)
1. Download [Rufus](https://rufus.ie/).
2. Insert your USB flash drive.
3. Select `revenant_os_1.0_build17.iso`.
4. Partition scheme: **MBR**, Target system: **BIOS or UEFI**.
5. Click **Start**. When prompted, select **Write in DD Image mode** (recommended for hybrid bootloaders).

### Option B: Using BalenaEtcher (Windows / macOS / Linux)
1. Open BalenaEtcher.
2. Select `revenant_os_1.0_build17.iso`.
3. Select your target USB stick.
4. Click **Flash!**.

---

## Booting on Panasonic Toughbook CF-52
1. Plug the flashed USB stick into one of the Toughbook's USB ports.
2. Power on the laptop and immediately tap the **F2** key repeatedly to enter the BIOS Setup Utility.
3. Use the arrow keys to navigate to the **Boot** tab.
4. Highlight **USB Drive** (or **USB HDD**) and press `F6` to move it to the top of the boot priority list.
5. Press `F10` to save changes and exit.
6. The high-definition **Revenant OS GRUB bootloader** will appear. Select `Revenant OS - Agentic Core`.
7. The full-screen Revenant cyber boot splash will display as drivers load.
8. The system automatically enters the live environment.

---

## Hard Drive Installation
1. Double-click **"Install Revenant OS"** on the live desktop.
2. Enter your desired **Username**, **Password**, and **Computer Hostname**.
3. Choose the target internal drive (e.g. `/dev/sda`).
4. Review the final confirmation prompt and click **"Yes, Erase & Install"**.
5. The installer will partition, format (ext4), replicate system files, configure the bootloader, and prepare user credentials.
6. When the success notification appears, reboot and remove the USB drive.

---

## First Boot & Session Selection
1. On boot, the system presents the **LightDM Login Screen**.
2. Select your newly created user account and type your password.
3. In the top bar of the login screen, click the session dropdown to select:
   - **Xfce Session**: Traditional full graphical desktop.
   - **i3**: Ultra-lightweight tiling window manager.
4. You can also switch between environments at any time while logged in by running `switch-to-i3` or `switch-to-xfce` in any terminal.
