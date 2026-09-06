# Agentic AI Core & Local Inference Architecture

## Overview
Revenant OS is engineered from the ground up to be **Local-First**. It provides a fully functioning, high-performance offline AI agent stack that runs on the Toughbook CF-52's CPU without needing an internet connection, accounts, or subscriptions.

---

## Core Inference Stack

### 1. Embedded `llama-server` (`:8080`)
- **System Service**: Managed automatically by `systemd` (`llama-server.service`).
- **Binary Location**: `/opt/llama.cpp/llama-server`
- **Default Port**: `http://127.0.0.1:8080/v1` (OpenAI-compatible)
- **Active Model**: `Qwen2.5-Coder-1.5B-Instruct` (Q4_K_M GGUF) in `/opt/models/`
- **Attention & KV Cache Architecture**:
  - Configured with a **4,096 token context window** (`--ctx-size 4096`).
  - Uses full-fidelity `f16` Key-Value attention cache (Build 15.3 golden configuration). This completely avoids 4-bit KV quantization errors (`q4_0`), ensuring coherent reasoning, syntax accuracy, and zero repetitive stutter loops.
  - Resource usage: ~1.6 GB total RAM on CPU (fits comfortably inside 4 GB RAM).
- **Service Management**:
  ```bash
  sudo systemctl status llama-server
  sudo systemctl restart llama-server
  ```

### 2. Universal Terminal AI (`ai`)
Revenant OS provides an instant command-line AI assistant accessible from any shell:
```bash
ai "How do I check battery capacity on this Toughbook?"
ai "Write a bash one-liner to parse failed logins in /var/log/auth.log"
```
- Sends the prompt to `http://127.0.0.1:8080/v1/chat/completions`.
- Formats and displays the response directly in the terminal.
- Automatically speaks the response aloud using the offline Piper neural TTS engine.

### 3. OpenViking Automated Context Database
- **System Service**: `openviking.service`
- Runs in the background, continuously storing agent interactions, commands, and environment discoveries.
- Provides persistent memory across agent sessions without burning massive context tokens.
- Queryable via CLI:
  ```bash
  ov ls viking://resources/
  ov find "wifi configuration"
  ```

### 4. Autonomous Field Agents

#### Revenant Custom Agent (`revenant-agent`)
Revenant OS features a native, ultra-lightweight autonomous agent written in Python (`/usr/local/bin/revenant-agent`). Designed as a high-efficiency replacement for resource-heavy agent frameworks (such as Hermes), it operates with minimal token overhead and instant response times directly on Toughbook dual-core CPUs:

- **Autonomous Tool Execution Loop**:
  - `[EXEC: bash_command]` — Proposes bash commands for inspection or execution (e.g., hardware checks, package queries, network status). Prompts the user with `Execute? [Y/n/edit]` before running.
  - `[READ: filepath]` — Reads and inspects files up to 4,000 characters.
  - `[WRITE: filepath | content]` — Creates or overwrites configuration files or scripts.
  - Tool outputs are fed back into the reasoning loop for autonomous follow-up analysis.

- **Real-Time Hardware Telemetry**:
  - On launch and during operation, the agent displays a dynamic telemetry header:
    `Battery: 85% | Temp: 42.0°C | RAM: 1420/3890MB`

- **Interactive Commands**:
  - `/voice` — Toggles offline neural speech synthesis (Piper TTS) on or off in real time.
  - `/sys` — Executes instant Toughbook hardware and system diagnostics (`uname`, `uptime`, `free`, `df`, `sensors`).
  - `/clear` — Flushes conversation history back to the system prompt.
  - `exit` or `quit` — Exits the agent cleanly.

- **How to Launch**:
  ```bash
  revenant-agent
  ```
  Or run `ai` with no arguments, or click the **"Revenant Autonomous Agent"** desktop icon.

> [!NOTE]
> **Hermes Agent Decommissioning**  
> Prior builds experimented with Hermes Agent. However, Hermes enforced high context memory floors (>4,000 to 64,000 tokens) and background auxiliary models that saturated mobile CPU cores and triggered client timeouts. In Build 17, Hermes has been fully purged from the OS image and replaced with the native Revenant Custom Agent.

#### OpenInterpreter Setup
For multi-language code generation and automated script debugging, OpenInterpreter remains available and configured in `/etc/environment` pointing to `http://127.0.0.1:8080/v1`:
```bash
interpreter
```

### 5. Diagnostics & Stack Controller
Launch the integrated control dashboard anytime:
```bash
revenant-services
```
Or double-click the **"Start AI Engine & Services"** icon on your desktop.

### 6. Offline Neural Speech Synthesis (Piper TTS)
- Pre-packaged neural voice model: `en_US-lessac-medium.onnx` located in `/opt/piper/models/`.
- Fast, natural offline synthesis computed on CPU and streamed to ALSA audio.
