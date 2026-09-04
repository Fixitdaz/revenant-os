# Toughbook CF-52 Hardware Optimization

## Panasonic Hotkeys & Battery Diagnostics
- Driver: `panasonic-laptop`
- Battery charge limits, brightness keys, and thermal fan profiles are managed natively by the ACPI subsystem.
- Inspect battery health:
  ```bash
  upower -i /org/freedesktop/UPower/devices/battery_BAT1
  ```

## Legacy Graphics Acceleration
- Video driver: `xserver-xorg-video-intel`
- Mesa 3D DRI acceleration is enabled by default.
- Verify DRI status:
  ```bash
  glxinfo | grep "direct rendering"
  ```

## Power Management (TLP)
- TLP automatically switches between AC power profiles and battery saver profiles.
- Check current power profile:
  ```bash
  sudo tlp-stat -s
  ```

## Firewall (UFW)
- Revenant OS enables a strict default firewall:
  - **Incoming**: Denied
  - **Outgoing**: Allowed
  - **SSH**: Allowed (`22/tcp`)
  - **OmniRoute**: Local loopback only (`20128/tcp`)
- Check status:
  ```bash
  sudo ufw status verbose
  ```
