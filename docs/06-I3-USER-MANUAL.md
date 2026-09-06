# The Complete Beginner's Guide to i3 Window Manager in Revenant OS

> **"From Zero to Keyboard Master — A Simple, Jargon-Free Field Manual"**

Welcome to **i3** on Revenant OS! If you have only ever used Windows, macOS, or standard Linux desktop environments like XFCE or GNOME, i3 might look unfamiliar or even intimidating at first glance. 

**Do not panic.** i3 is designed to be faster, lighter, and much simpler once you learn a handful of key combinations. This guide assumes zero prior experience and explains everything in plain English.

---

## 1. The Big Picture: What is a "Tiling" Window Manager?

### The Traditional Desktop vs. i3
* **Traditional Desktops (Windows / XFCE)**: Windows open like pieces of paper scattered randomly across a physical desk. They overlap, hide behind each other, require you to grab edges with your mouse to resize them, and waste precious screen space.
* **i3 Tiling Window Manager**: Windows behave like **floor tiles or bricks in a wall**. Every window automatically slots into place, filling 100% of the available screen with zero wasted space. Windows **never overlap or get lost**.

### Why i3 is Built for the Panasonic Toughbook
1. **Blazing Fast**: Uses virtually 0% GPU and minimal RAM. Even on older Intel Core 2 Duo Toughbook hardware, it is instantaneous.
2. **Extended Battery Life**: Zero heavy compositing effects, blur filters, or background graphical baggage means your battery lasts significantly longer in the field.
3. **No Mouse Required**: When you are wearing heavy work gloves or operating in wet, muddy, or vibrational field conditions where a trackpad is frustrating to use, you can control your entire computer effortlessly using only the keyboard.

---

## 2. The Golden Key: The `Mod` Key

Almost every action in i3 begins by pressing one special key called the **`Mod` key**.

On your Panasonic Toughbook and most PC keyboards:
> ### 🪟 The `Mod` Key = The **Windows Key**
> (Located on the bottom-left row of your keyboard, between `Ctrl` and `Alt`, displaying the Windows flag icon).

Whenever you see:
* **`Mod + Enter`** — It means: **Hold down the Windows Key, press Enter, then let go.**
* **`Mod + Shift + Q`** — It means: **Hold down both the Windows Key and the Shift Key, press Q, then let go.**

---

## 3. The "Never Get Stuck" Quickstart (Top 7 Rules)

If you memorize only these 7 shortcuts, you can comfortably use i3 every day:

| Action | Shortcut Keys | What It Does (In Plain English) |
| :--- | :--- | :--- |
| **Open Terminal** | `Windows Key + Enter` | Opens a new command-line terminal window. |
| **Close Window** | `Windows Key + Shift + Q` | Closes the active window immediately (equivalent to clicking the red `X`). |
| **Open App Launcher** | `Windows Key + D` | Opens a search bar at the very top of your screen (`dmenu`). Type the name of any program (e.g. `firefox`) and hit `Enter`. |
| **AI Voice Assistant** | `Windows Key + M` | Activates the Revenant AI Field Agent with microphone listening. |
| **Instant Help** | `Windows Key + F1` | Pops open the on-screen Quick Reference Cheat Sheet. |
| **Switch to XFCE** | Type `switch-to-xfce` | Drops you instantly back into the full graphical mouse desktop without rebooting. |
| **Log Out / Exit i3** | `Windows Key + Shift + E` | Shows a red bar at the top asking if you want to exit. Click **"Yes, exit i3"** to return to the login screen. |

---

## 4. How Windows Open & Tile (Splitting Explained)

When you open applications in i3, they arrange themselves automatically:

1. **Your First Window**:
   - Press `Windows Key + Enter`.
   - A terminal opens and takes up **100% of the screen**.

2. **Your Second Window**:
   - Press `Windows Key + Enter` again.
   - i3 automatically cuts the screen in half: Window 1 is on the left, Window 2 is on the right.

3. **Where Does the Next Window Go? (Splitting)**:
   By default, i3 splits windows horizontally (side-by-side). You can tell i3 where to put your *next* window before opening it:
   * **`Windows Key + V` (Vertical Split)**: Tells i3: *"Place the next window **below** the current window."*
   * **`Windows Key + H` (Horizontal Split)**: Tells i3: *"Place the next window **beside** the current window."*

```
Default Horizontal Split:             After pressing Windows Key + V:
+-------------------+---------------+   +-------------------+---------------+
|                   |               |   |                   |   Window 2    |
|     Window 1      |   Window 2    |   |     Window 1      +---------------+
|                   |               |   |                   | Window 3 (New)|
+-------------------+---------------+   +-------------------+---------------+
```

---

## 5. Moving Around & Rearranging Windows

### Moving Your Focus (Which Window You Are Typing In)
You never need to touch the mouse to click on a window. Just hold the **Windows Key** and look at your arrow keys:

* **`Windows Key + Left Arrow`** — Move focus to the window on the left.
* **`Windows Key + Right Arrow`** — Move focus to the window on the right.
* **`Windows Key + Up Arrow`** — Move focus to the window above.
* **`Windows Key + Down Arrow`** — Move focus to the window below.

*(Pro Tip for touch-typists: You can also use the home-row Vim keys: `Mod + J` for left, `Mod + K` for down, `Mod + L` for up, and `Mod + ;` for right).*

### Shuffling Windows to New Positions
Want to move a window to the other side of the screen? Just add the **`Shift`** key:

* **`Windows Key + Shift + Left Arrow`** — Shift active window to the left.
* **`Windows Key + Shift + Right Arrow`** — Shift active window to the right.
* **`Windows Key + Shift + Up Arrow`** — Shift active window upward.
* **`Windows Key + Shift + Down Arrow`** — Shift active window downward.

---

## 6. Layout Styles: Split, Tabs, Stacks & Fullscreen

i3 gives you four distinct ways to view your windows:

### 1. Fullscreen Mode (`Windows Key + F`)
* Press **`Windows Key + F`** to make the current window fill the entire monitor.
* Press **`Windows Key + F`** again to return it back to its tiled position.

### 2. Tabbed Layout (`Windows Key + W`)
* Think of browser tabs. All windows on your screen collapse into full-sized views with a row of clickable tabs across the top.
* Press **`Windows Key + Left/Right Arrow`** to flip between tabs.

### 3. Stacked Layout (`Windows Key + S`)
* Similar to tabs, but the title bars are stacked vertically on top of each other.

### 4. Standard Split Layout (`Windows Key + E`)
* Returns your windows back to the standard side-by-side / tiled view.

### 5. Floating Windows (`Windows Key + Shift + Space`)
* Want a window to behave like traditional Windows (floating on top, draggable)?
* Press **`Windows Key + Shift + Space`** on any window. It will pop out of the tile grid!
* **To Move a Floating Window**: Hold down **`Windows Key`**, then **left-click and drag** the window anywhere with your mouse.
* **To Resize a Floating Window**: Hold down **`Windows Key`**, then **right-click and drag** to expand or shrink it.
* Press **`Windows Key + Shift + Space`** again to snap it back into the tiling grid.

---

## 7. Workspaces: 10 Clean Desktops at Your Fingertips

Instead of cluttering one screen with 20 windows, i3 gives you **Workspaces** (virtual desktops numbered 1 through 10).

Look at the bottom-left corner of your screen on the status bar. You will see numbers like `1`, `2`, `3`.

### Switching Workspaces
* **`Windows Key + 1`** — Jump to Workspace 1.
* **`Windows Key + 2`** — Jump to Workspace 2.
* **`Windows Key + 3`** — Jump to Workspace 3.
* *(Works all the way up to `Windows Key + 9` and `Windows Key + 0`)*.

### Sending a Window to Another Workspace
Want to clean up your screen and send an app to Workspace 2?
1. Click or focus the window you want to move.
2. Press **`Windows Key + Shift + 2`**.
3. The window instantly teleports to Workspace 2!
4. Press **`Windows Key + 2`** whenever you want to go work on it.

### Recommended Field Setup:
* **Workspace 1**: Primary terminal and monitoring.
* **Workspace 2**: Offline AI Agent (`revenant-agent`).
* **Workspace 3**: Web browser (`firefox`) or system utilities.
* **Workspace 4**: File manager (`thunar`) or PDF documentation.

---

## 8. Resizing Windows (The Simple 3-Step Method)

Because i3 doesn't rely on tiny window borders that are difficult to grab with a mouse, resizing is done through **Resize Mode**:

1. **Step 1: Enter Resize Mode**
   * Select the window you want to resize.
   * Press **`Windows Key + R`**.
   * Notice that the status bar at the bottom or top will show: `[resize]`.
2. **Step 2: Adjust the Size**
   * Press the **`Left / Right / Up / Down Arrow`** keys repeatedly until the window is the exact size you want.
3. **Step 3: Lock It In**
   * Press **`Enter`** or **`Escape`** (`Esc`).
   * The `[resize]` indicator disappears, and you are back to normal typing!

*(Mouse Alternative: If you prefer using your mouse, simply hold down the **`Windows Key`**, **right-click inside the window**, and drag your mouse to resize).*

---

## 9. Opening Any Application (`dmenu`)

You don't need an application menu button to start software:

1. Press **`Windows Key + D`**.
2. A horizontal bar will appear across the very top of your screen displaying installed programs.
3. Simply start typing what you want:
   * Type `fire` → it highlights `firefox`.
   * Type `thu` → it highlights `thunar` (file manager).
   * Type `hids` or `htop` → it highlights system monitors.
4. Press **`Enter`**. The application launches immediately.
5. If you change your mind and want to close the launcher, press **`Escape`** (`Esc`).

---

## 10. Revenant OS AI & Voice Controls in i3

Revenant OS is deeply integrated into i3:

* **`Windows Key + M`**: Activates the single-window **Revenant AI Field Assistant** with offline Whisper voice transcription.
  * If the agent is already open on another workspace or behind other windows, it automatically brings it to the front and turns on the microphone.
  * Zero duplicate windows are opened.
  * Your speech is transcribed and pre-filled directly into the interactive prompt buffer (`revenant ❯ ...`). Hit **Enter** to submit!
* **`Ctrl + Alt + M`**: Alternative voice hotkey.
* **`Windows Key + F1`**: On-screen Quick Reference manual.

---

## 11. Understanding the Bottom Status Bar (`i3status`)

Across the bottom of the screen is the live status bar:

* **Workspace Numbers (Left)**: Shows active workspaces. Workspaces with active windows are highlighted.
* **IP Address / Network**: Displays your local IPv4 address on Ethernet (`eth0`) or Wi-Fi (`wlan0`).
* **Disk Space**: Shows available free space on the root filesystem (e.g. `24.5 GB`).
* **Battery Level**: Shows live Panasonic Toughbook battery percentage and charging/discharging status.
* **Clock & Date**: High-visibility local timestamp.

---

## 12. Master Keybinding Cheat Sheet

Keep this table handy or press **`Windows Key + F1`** inside i3 anytime:

| Category | Shortcut Key Combination | Description |
| :--- | :--- | :--- |
| **Core** | `Windows Key + Enter` | Open Terminal |
| **Core** | `Windows Key + D` | Open App Launcher (`dmenu`) |
| **Core** | `Windows Key + Shift + Q` | Close Active Window |
| **Core** | `Windows Key + F1` | Show On-Screen Help & Cheat Sheet |
| **AI** | `Windows Key + M` | AI Voice Assistant (Microphone Mode) |
| **AI** | `Ctrl + Alt + M` | Secondary Voice Assistant Hotkey |
| **Navigation** | `Windows Key + Arrow Keys` | Move Focus (Left / Right / Up / Down) |
| **Navigation** | `Windows Key + J / K / L / ;` | Move Focus (Vim-style Left/Down/Up/Right) |
| **Moving** | `Windows Key + Shift + Arrow Keys` | Shift Window Position |
| **Layout** | `Windows Key + V` | Vertical Split (Next window opens below) |
| **Layout** | `Windows Key + H` | Horizontal Split (Next window opens beside) |
| **Layout** | `Windows Key + F` | Toggle Fullscreen Mode |
| **Layout** | `Windows Key + W` | Tabbed Layout (Browser-style tabs) |
| **Layout** | `Windows Key + S` | Stacking Layout |
| **Layout** | `Windows Key + E` | Default Tiling Split Layout |
| **Floating** | `Windows Key + Shift + Space` | Toggle Window Between Tiled & Floating |
| **Floating** | `Windows Key + Left-Click Drag` | Move Floating Window with Mouse |
| **Floating** | `Windows Key + Right-Click Drag`| Resize Floating Window with Mouse |
| **Workspaces**| `Windows Key + 1` to `9` | Jump to Workspace 1 through 9 |
| **Workspaces**| `Windows Key + Shift + 1` to `9`| Send Active Window to Workspace 1 through 9|
| **Resizing** | `Windows Key + R` | Enter Resize Mode (Use Arrows, hit Esc to finish) |
| **System** | `Windows Key + Shift + E` | Exit / Log Out of i3 (Returns to Login Screen) |
| **System** | `switch-to-xfce` (in terminal) | Switch to XFCE graphical desktop instantly |

---

## 13. "Don't Panic!" — Troubleshooting Common Scenarios

### Q: "My screen went completely blank/black! Did my system crash?"
* **Answer**: No! You almost certainly switched to an empty workspace.
* **Fix**: Press **`Windows Key + 1`** to return to Workspace 1 where your windows are, or press **`Windows Key + Enter`** to open a new terminal wherever you are.

### Q: "A window took over my entire screen and all borders disappeared!"
* **Answer**: You accidentally pressed Fullscreen mode.
* **Fix**: Press **`Windows Key + F`** to toggle back to normal tiled mode.

### Q: "I pressed `Windows Key + D` and there's a bar at the top, but I don't want to open anything."
* **Answer**: Press **`Escape`** (`Esc`) to cancel the launcher.

### Q: "How do I get back to the normal mouse-friendly desktop?"
* **Answer**: You have two easy ways:
  1. Open a terminal (`Windows Key + Enter`) and run:
     ```bash
     switch-to-xfce
     ```
  2. Or press **`Windows Key + Shift + E`**, click the red prompt to log out, and on the LightDM login screen, select **Xfce Session** from the top-right menu before entering your password.
