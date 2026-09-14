---
name: electronics-repair
description: Expert electronics repair and component-level troubleshooting. Diagnostics, PCB repair, schematics, and hardware troubleshooting.
---

# Electronics Repair & Diagnostics Skill

This skill provides comprehensive guidelines, diagnostics protocols, and repair procedures for component-level electronics troubleshooting, printed circuit board (PCB) repair, and hardware debug.

---

## 1. Safety & Preparation Protocols

### Critical Safety Rules
*   **High Voltage Safety**: When working with mains-connected power supplies or high-voltage circuits (CRTs, tube amps, inverter boards):
    *   Always discharge large filtering capacitors (e.g., mains bulk caps) using a dedicated discharge resistor tool (e.g., 100Ω to 1kΩ power resistor). **Never short capacitor terminals with a screwdriver.**
    *   Work with one hand in your pocket when probing live high-voltage circuits to prevent a current path through your heart.
    *   Use an isolation transformer for mains-powered device testing.
*   **ESD Precautions**: Use an ESD-safe mat, wrist strap, and dissipative containers for sensitive ICs (MOSFETs, microcontrollers, RF chips).
*   **Battery Handling**: Check for swollen or damaged Lithium-Polymer (LiPo) / Lithium-Ion batteries. Never puncture, bend, or heat batteries. Have a fire-suppression bucket (sand) nearby.

---

## 2. Systematic Diagnostic Framework

Follow this phase-based troubleshooting flow for any broken device:

### Phase 1: Visual Inspection (The "Eyes-On" Check)
Always inspect the board under magnification before applying power:
*   **Corrosion / Liquid Damage**: Look for white/green powder, rust, or sticky residues.
*   **Thermal Distress**: Check for charred PCBs, cracked component packages, bubbled IC casings, or discolored copper.
*   **Solder Failures**: Look for cracked joints, cold solder joints (dull/grainy), solder balls, or whisker shorts.
*   **Mechanical Damage**: Torn pads, ripped ribbon connector tabs, bent connector pins, and cracked traces near mount holes.

### Phase 2: Input & Power Rail Checks (Unpowered)
Before injecting power, check key rails for direct short circuits:
*   Set your multimeter to **Continuity mode** or **Resistance mode**.
*   Probe the main input (DC jack, USB port, battery connector).
*   Probe the output inductors/coils of buck/boost regulators.
*   *Interpretation*: A reading < 5Ω to Ground on a high-voltage rail (e.g., 12V, 19V) or 5V rail indicates a short circuit. Low-voltage CPU/GPU core rails (e.g., 0.8V - 1.2V) naturally have low resistance (often 1Ω - 15Ω); do not mistake this for a dead short.

### Phase 3: Live Diagnostic Probing (Powered)
If no direct input short exists, apply power using a current-limited bench power supply:
*   Set supply voltage to the device's native voltage.
*   Set current limit to a safe threshold (e.g., 100mA - 200mA for small logic boards, 1A for larger systems).
*   **Observe current draw**:
    *   *Direct short-circuit behavior*: Power supply hits current limit instantly, dropping output voltage.
    *   *No-power behavior*: 0.00A draw (blown input fuse, bad DC-in MOSFET, open circuit).
    *   *Half-power/Stuck behavior*: Minor current draw (e.g., 50mA) but no boot activity (missing power-good signal, dead reset line, bad firmware).

### Phase 4: Short Circuit Hunting (Thermal Diagnostics)
If a power rail is shorted:
1.  Set bench power supply voltage to the nominal rail voltage (never exceed it).
2.  Set current limit to 1A - 2A.
3.  Inject voltage directly into the shorted rail.
4.  **Identify the heating component**:
    *   *Isopropyl Alcohol (IPA) method*: Spray 99% IPA on the board. The shorted component (usually a MLCC capacitor or PMIC) will heat up and evaporate the IPA first.
    *   *Thermal Camera*: Check for hot spots.
    *   *Rosin flux method*: Melt rosin vapor onto the board to form a white frost; the shorted component will melt the rosin instantly.

---

## 3. Tool Workflows & Measurement Interpretation

### Multimeter Workflows
*   **Diode Mode**: 
    *   Red probe to Ground, Black probe to signal line (reverse bias).
    *   *Utility*: Tests the health of ESD protection diodes, IC input pins, and signal rails.
    *   *Interpretation*: A normal reading is between 0.3V and 0.8V. A reading of 0.0V indicates a shorted line. A reading of "OL" (Open Loop) indicates a broken trace or failed connection.
*   **Resistance / Continuity**:
    *   Always measure with the circuit fully powered down and capacitors discharged.
*   **Capacitance**:
    *   Desolder at least one leg of the capacitor to get an accurate value. Check the Equivalent Series Resistance (ESR) of electrolytic capacitors; high ESR indicates a failing capacitor even if the capacitance is correct.

### Oscilloscope Diagnostics
*   **Power Rail Ripple**: Measure power rails with AC coupling enabled. High ripple (voltage spikes/noise) indicates failed output filtering capacitors.
*   **Crystal Oscillators**: Probe the leads of crystal oscillators. Look for a stable sine wave at the marked frequency (e.g., 16MHz, 32.768kHz).
*   **Communication Busses (I2C, SPI, UART)**: Look for clean square waves with fast rise/fall times. If signals are rounded or don't reach logic high (e.g., VCC), check for missing pull-up resistors or bus loading.

---

## 4. Component-Level Repair Procedures

### Soldering & Desoldering Best Practices
*   **Flux is Mandatory**: Always use high-quality tacky no-clean flux. Flux cleans oxide layers and improves heat transfer.
*   **Temperature Selection**:
    *   Lead-based solder (Sn63/Pb37): 300°C - 320°C.
    *   Lead-free solder (SAC305): 340°C - 370°C.
    *   High-thermal-mass ground planes: 380°C - 400°C (use a wide chisel tip to maximize contact surface area).
*   **BGA & QFN Rework**:
    *   Use a hot-air station with appropriate nozzles.
    *   Keep the nozzle moving to avoid localized board warping.
    *   For BGA chips, wait for the solder to liquify fully (observe chip "settling" or gently nudge the chip; surface tension will pull it back if all joints are molten).

### PCB Trace Repair
1.  Scrape away the solder mask on both sides of the break to expose the copper traces.
2.  Apply flux and tin the exposed copper.
3.  Bridge the gap using a single strand of copper wire (e.g., 0.02mm enameled jumper wire).
4.  Coat the repaired area with UV-curable solder mask resin.
5.  Cure with a UV flashlight for 30-60 seconds.

---

## 5. Troubleshooting Checklists by Failure Mode

### Failure Mode: Completely Dead (No Power, No Lights)
*   [ ] Verify the external power adapter output voltage is correct.
*   [ ] Test input fuse and input reverse-polarity protection diode for continuity.
*   [ ] Check the first input MOSFET(s) gating the power input.
*   [ ] Verify the primary 3.3V and 5V Always-On (LDO) rails are present.
*   [ ] Check the power button signal line: does it toggle from high (e.g., 3.3V) to low (0V) when pressed?

### Failure Mode: Boot Loop / Power Cycles
*   [ ] Measure all secondary power rails during the brief power-on window.
*   [ ] Verify the PMIC "Power Good" signals are asserting high.
*   [ ] Check for overheating ICs immediately after power-on.
*   [ ] Verify the SPI Flash chip containing bios/firmware is receiving clock/data signals.
*   [ ] Reflash BIOS/Firmware to rule out data corruption.
