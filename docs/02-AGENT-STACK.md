# Agentic AI Core Architecture & Usage

## Overview
Revenant OS features a native, pre-installed AI agent stack designed for sovereign edge computing and multi-agent coordination.

---

## Core Components

### 1. OmniRoute AI Gateway (`:20128`)
- **Daemon**: Managed by `systemctl status omniroute.service`.
- **Purpose**: A local OpenAI-compatible API gateway and proxy that handles multi-provider routing, load balancing, rate limiting, and fallback across local and cloud models.
- **Port**: `20128` on `localhost`.

### 2. Universal Terminal Assistant (`ai`)
You can invoke the AI assistant directly from any terminal session (Fish shell or Bash):
```bash
ai "Summarize the last 50 lines of dmesg and check for hardware errors"
```
```bash
ai "Write a bash script to monitor wifi signal strength every 5 seconds"
```

### 3. OpenInterpreter
Execute tasks using natural language:
```bash
interpreter
```
OpenInterpreter connects directly to the local Python and shell runtime, enabling automated file management, data processing, and scripting.

### 4. OpenViking Context Database
- Integrates persistent memory and vector embeddings for agent workflows.
- Accessible via the `ov` CLI:
  ```bash
  ov ls viking://resources/
  ```

### 5. Offline Neural Speech (Piper)
Revenant OS uses **Piper TTS** to speak agent responses asynchronously without cloud latency:
- Neural voice models reside in `/opt/piper/models/`.
- Test voice synthesis manually:
  ```bash
  echo "Revenant OS core systems online." | /opt/piper/piper -m /opt/piper/models/en_US-lessac-medium.onnx --output_raw | aplay -r 22050 -f S16_LE -t raw -
  ```
