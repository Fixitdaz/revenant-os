# Over-The-Air (OTA) Update System

## How It Works
Revenant OS includes a dedicated OTA update utility (`revenant-update`) that synchronizes the operating system over the internet without needing fresh ISO installs.

---

## Running an Update

### 1. Check for Updates
To see if a new build or security patch is available:
```bash
sudo revenant-update --check
```

### 2. Apply All Updates
To download and install the latest components:
```bash
sudo revenant-update
```

---

## Update Layers
1. **Agent Core Layer**:
   - Pulls the latest `omniroute`, `hermes-agent`, `openviking`, and `open-interpreter` packages.
   - Automatically restarts the `omniroute.service` systemd unit.
2. **Offline Speech Layer**:
   - Checks `/opt/piper/models/` and downloads updated voice models if missing or upgraded.
3. **Hardware & Configuration Layer**:
   - Synchronizes Toughbook hotkey drivers, terminal aliases, and desktop profiles.
4. **Base System Security Layer**:
   - Executes non-interactive package index update and security upgrades via APT.
