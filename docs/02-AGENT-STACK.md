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
  - Configured with a **20,480 token context window** (`--ctx-size 20480`).
  - Uses full-fidelity `f16` Key-Value attention cache. This completely avoids 4-bit KV quantization errors (`q4_0`), ensuring coherent reasoning, syntax accuracy, and zero repetitive stutter loops.
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

### 4. Autonomous Agents (Hermes Agent & OpenInterpreter)
Revenant OS pre-configures environment variables in `/etc/environment`:
```bash
OPENAI_API_BASE="http://127.0.0.1:8080/v1"
OPENAI_API_KEY="sk-local-revenant"
```

#### Hermes Agent Setup
Hermes Agent configuration (`~/.hermes/config.yaml`) includes a declared local provider:
```yaml
model:
  default: "qwen2.5-coder-1.5b-instruct"
  provider: "custom"
  base_url: "http://127.0.0.1:8080/v1"
  context_length: 20480
custom_providers:
  - name: "local"
    base_url: "http://127.0.0.1:8080/v1"
    models:
      qwen2.5-coder-1.5b-instruct:
        context_length: 20480
auxiliary:
  compression:
    model: "qwen2.5-coder-1.5b-instruct"
    context_length: 20480
toolsets:
  - "hermes-cli"
```
To launch an interactive session:
```bash
hermes
```

#### OpenInterpreter Setup
To launch an interactive local coding agent:
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
