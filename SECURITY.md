# Security Policy

## Supported Versions

Revenant OS actively supports and provides Over-The-Air (`sudo revenant-update`) security patches for the following branches and releases:

| Version / Channel | Supported |
| :--- | :--- |
| **Build 20.x (`main` — Stable OTA Channel)** | ✅ Supported |
| **Build 20.x (`beta` — Testing OTA Channel)** | ✅ Supported |
| **< Build 19.0** | ❌ Unsupported (upgrade via `sudo revenant-update`) |

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Instead, report security vulnerabilities privately via email to the primary maintainer and security contact:

- **Primary Security Contact**: `fixitdaz@gmail.com`
- **Project Maintainer**: Daz (`@Fixitdaz`)

### What to Include
1. A clear description of the vulnerability and the affected component (e.g., `revenant-agent`, `tools/revenant-update`, `omniroute-setup-free`, or system hooks).
2. Steps to reproduce the issue or a minimal proof-of-concept script.
3. Any suggested remediation or patch, if available.

### Threat Model & Automated Auditing
Revenant OS maintains an explicit security threat model and isolated build configuration for automated vulnerability scanning in:
- [`.oss-scanner/threat_model.md`](.oss-scanner/threat_model.md)
- [`.oss-scanner/Dockerfile`](.oss-scanner/Dockerfile)
