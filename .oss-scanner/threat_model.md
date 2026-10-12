# Revenant OS — Threat Model for Anthropic OSS Scanner

## 1. Project Overview
**Revenant OS** (`https://github.com/Fixitdaz/revenant-os`) is a Debian 12 (Bookworm) Live/Installable Linux distribution and autonomous AI operating environment engineered specifically for rugged field hardware (Panasonic Toughbook CF-19 / CF-31) and constrained edge laptops.

It provides:
1. **Revenant Agent (`config/includes.chroot/usr/local/bin/revenant-agent`)**: A terminal-first, hardware-aware autonomous agent capable of switching between a 100% offline local CPU LLM engine (`llama-server` on `127.0.0.1:8080`) and an online multi-provider Cloud AI router (`OmniRoute` on `127.0.0.1:20128`).
2. **OTA Updater (`tools/revenant-update`)**: A root-privileged Over-The-Air update utility that pulls verified system updates from the official GitHub repository (`main` or `beta` channels) and applies them to the live/installed filesystem without reflashing the ISO.
3. **OmniRoute Provisioning (`config/includes.chroot/usr/local/bin/omniroute-setup-free`)**: A provisioning and credential-injection script that configures free-tier cloud LLM providers in a local SQLite database and restarts the local routing service.
4. **Hardware & Radio Control Scripts (`config/includes.chroot/usr/local/bin/*`)**: System utilities for Panasonic Toughbook touchscreens, tablet hinges, GPS/WWAN modems, and power management.

---

## 2. In-Scope Components & Trust Boundaries

### Primary Audit Targets (In Scope)
| Component | Path in `/src` | Installed Path | Privilege Level |
| :--- | :--- | :--- | :--- |
| **Revenant Agent** | `config/includes.chroot/usr/local/bin/revenant-agent` | `/usr/local/bin/revenant-agent` | Standard User (`toughbook` with `sudo` capabilities) |
| **OTA Updater** | `tools/revenant-update` | `/usr/local/bin/revenant-update` | `root` (via `sudo`) |
| **OmniRoute Setup** | `config/includes.chroot/usr/local/bin/omniroute-setup-free` | `/usr/local/bin/omniroute-setup-free` | Standard User / `sudo` for systemd restart |
| **Chroot System Scripts & Hooks** | `config/includes.chroot/usr/local/bin/*`, `config/hooks/live/*` | `/usr/local/bin/*` | `root` or Standard User |
| **ISO Builder** | `build_iso.sh` | `/src/build_iso.sh` | `root` (build host) |

### Untrusted Inputs
1. **Remote LLM / Cloud Router Responses (`127.0.0.1:20128/v1/chat/completions`)**:
   - When operating in `CLOUD` mode, `revenant-agent` parses Server-Sent Events (`data: ...`) and raw JSON responses from external cloud LLM providers routed through OmniRoute.
   - Responses may contain malformed JSON, unexpected control characters, or adversarial prompt-injected tool tags (`[EXEC: ...]`, `[READ: ...]`, `[WRITE: ...]`).
2. **Skill Files & External Content**:
   - Files read via `[READ: ...]` or skills loaded from `/opt/revenant-os/skills/` may contain untrusted text that is fed back into the LLM context window (indirect prompt injection).
3. **Network Responses During OTA Updates (`tools/revenant-update`)**:
   - Channel metadata, git refs, file paths inside downloaded archives/repositories, and temporary directories (`/tmp/revenant-ota-*`).
4. **Local IPC & Temporary Files (`/tmp/*`)**:
   - Predictable temporary filenames, symlink races in `/tmp`, or insecure file permissions on stored API keys and SQLite databases (`~/.omniroute/storage.sqlite`).

---

## 3. Intentional Design Features (Out of Scope / Not Vulnerabilities)

To prevent false positives, the scanner **must NOT report** the following intentional architectural behaviors as vulnerabilities:

1. **User-Approved `[EXEC: ...]`, `[READ: ...]`, and `[WRITE: ...]` Tool Execution**:
   - `revenant-agent` is explicitly designed as a system administration agent that executes shell commands (`subprocess.run(..., shell=True)`) and reads/writes files **after** the user explicitly approves the action at the `[Y/n]` prompt (when `KAMIKAZE_MODE = False`).
2. **Kamikaze Mode (`/kamikaze on`)**:
   - When the local human operator explicitly enables `/kamikaze on`, the agent intentionally bypasses per-step `[Y/n]` confirmation prompts so it can complete multi-step autonomous tasks. This is an explicit opt-in operator mode (default is `KAMIKAZE_MODE = False`).
3. **Passwordless `sudo` on a Single-User Live Field ISO**:
   - As a dedicated Debian Live hardware recovery and field-operations appliance, the live user (`toughbook`) is intentionally granted administrative privileges inside the live environment.

---

## 4. What Constitutes a Valid Vulnerability (Severity Guide)

### Critical Severity
- **Confirmation Gate Bypass (`KAMIKAZE_MODE = False`)**: Any bug in `revenant-agent` where a crafted LLM response, terminal escape sequence, or regex parsing flaw allows a command or file write to execute **without** user approval when `KAMIKAZE_MODE` is `False` (or silently toggles `KAMIKAZE_MODE` on via LLM output rather than user CLI input).
- **UI Spoofing / Terminal Escape Injection in Confirmation Prompts**: If an untrusted LLM response uses ANSI/VT100 escape sequences or carriage returns inside `[EXEC: ...]` or `[WRITE: ...]` to hide the actual command being approved by the user at the `[Y/n]` prompt.
- **Remote Code Execution / Arbitrary File Overwrite in `tools/revenant-update`**: Path traversal, command injection via crafted filenames, or symlink race conditions in `/tmp` during OTA updates.

### High Severity
- **Credential Exposure in `omniroute-setup-free` or `revenant-agent`**: World-readable API key storage (`0644` instead of `0600`), leaking API keys in process arguments (`ps aux`), or SQL injection / shell injection when inserting user-provided API keys into `~/.omniroute/storage.sqlite` in `omniroute-setup-free`.
- **Parser Denial of Service / Infinite Loop**: Malformed SSE or JSON payloads from a cloud provider causing unhandled crashes, unbounded memory allocation, or infinite autonomous tool loops exceeding `max_steps`.

### Medium Severity
- **Insecure Temporary File Handling**: Use of predictable `/tmp` paths without `mktemp -d` or `tempfile.NamedTemporaryFile` in root scripts (`tools/revenant-update`, `build_iso.sh`, hardware utilities) that could allow local symlink attacks.
- **Argument / Shell Injection in Helper Scripts**: Unquoted variable expansions or unsafe `eval`/SQLite interpolation in bash utilities under `config/includes.chroot/usr/local/bin/`.

---

## 5. Report & Patch Preferences
- Include a minimal, self-contained reproduction command or Python/Bash test script demonstrating the issue inside `/src`.
- Ensure proposed patches preserve compatibility with Python 3.11+ (Debian 12 Bookworm standard library + `requests` + `prompt_toolkit`) and POSIX/Bash scripts without introducing heavy external dependencies.
