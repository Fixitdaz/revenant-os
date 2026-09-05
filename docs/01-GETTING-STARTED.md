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
3. Select `revenant_os_toughbook_v15.iso`.
4. Partition scheme: **MBR**, Target system: **BIOS or UEFI**.
5. Click **Start**. When prompted, select **Write in DD Image mode** (recommended for hybrid bootloaders).

### Option B: Using BalenaEtcher (Windows / macOS / Linux)
1. Open BalenaEtcher.
2. Select `revenant_os_toughbook_v15.iso`.
3. Select your target USB stick.
4. Click **Flash!**.

---

## Booting on Panasonic Toughbook CF-52
1. Plug the flashed USB stick into one of the Toughbook's USB ports.
2. Power on the laptop and immediately tap the **F12** key repeatedly.
3. In the boot device selection list, highlight **USB HDD** or your flash drive model, then press **Enter**.
4. The high-definition **Revenant OS GRUB bootloader** will appear. Select `Revenant OS - Agentic Core`.
5. The full-screen Revenant cyber boot splash will display as drivers load.
6. The system automatically logs into the live environment.

---

## Hard Drive Installation
1. Double-click **"Install Revenant OS"** on the live desktop.
2. Enter your desired **Username**, **Password**, and **Computer Hostname**.
3. Choose the target internal drive (e.g. `/dev/sda`).
4. Review the final confirmation prompt and click **"Yes, Erase & Install"**.
5. The installer will partition, format (ext4), replicate system files, configure the bootloader, and un-divert initramfs updates.
6. When the success notification appears, reboot and remove the USB drive.
