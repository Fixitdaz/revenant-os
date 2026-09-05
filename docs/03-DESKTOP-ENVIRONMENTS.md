# Dual Desktop Environments: XFCE & i3

Revenant OS provides two fully configured desktop environments tailored for different field operation workflows:

1. **XFCE Desktop**: A full graphical desktop environment featuring windows, dock panels, system trays, application menus, and mouse controls.
2. **i3 Window Manager**: An ultra-lightweight, purely keyboard-driven tiling window manager maximized for screen real-estate, rapid multi-terminal multiplexing, and zero GPU overhead.

---

## Choosing Your Desktop Session

### Method 1: At the LightDM Login Screen (On Boot or After Logout)
1. On boot or after logging out, you are presented with the **LightDM Login Screen**.
2. Select your username and enter your password.
3. In the upper-right corner of the screen, click the session selector dropdown:
   - Select **Xfce Session** for the standard graphical desktop.
   - Select **i3** for the tiling window manager.
4. LightDM will remember your choice for subsequent logins until you change it.

### Method 2: On-the-Fly Desktop Switching (Without Rebooting)
You do not need to reboot to switch between XFCE and i3:
- **To switch from XFCE to i3**:
  - Double-click the **"Switch to i3"** icon on your desktop, or
  - Run the following command in any terminal:
    ```bash
    switch-to-i3
    ```
- **To switch from i3 to XFCE**:
  - Open dmenu (`Mod + d`), type `switch-to-xfce`, and press `Enter`, or
  - Run the following command in your terminal:
    ```bash
    switch-to-xfce
    ```

---

## i3 Window Manager Cheat Sheet

### Essential Hotkeys
- **Mod Key**: `Windows Key` (Super)
- **Open Terminal**: `Mod + Enter`
- **Application Launcher (dmenu)**: `Mod + d`
- **Close Active Window**: `Mod + Shift + q`
- **Open Help / Cheat Sheet**: `Mod + F1`
- **Log Out / Exit i3**: `Mod + Shift + e`

### Window Navigation
- **Focus Window**: `Mod + Arrow Keys` (or `Mod + j/k/l/;`)
- **Move Window**: `Mod + Shift + Arrow Keys`
- **Switch Workspace**: `Mod + 1` through `Mod + 9`
- **Move Window to Workspace**: `Mod + Shift + 1` through `Mod + 9`

### Window Layout & Splitting
- **Horizontal Split (Next window beside current)**: `Mod + h`
- **Vertical Split (Next window below current)**: `Mod + v`
- **Toggle Fullscreen**: `Mod + f`
- **Toggle Floating Window Mode**: `Mod + Shift + Space`
- **Resize Mode**: `Mod + r` (use arrow keys to adjust, press `Esc` to exit resize mode)

---

## Restoring Default Configurations
If you ever need to restore your desktop shortcuts or configuration files to stock settings:
```bash
cp /etc/skel/Desktop/*.desktop ~/Desktop/
chmod +x ~/Desktop/*.desktop
```
