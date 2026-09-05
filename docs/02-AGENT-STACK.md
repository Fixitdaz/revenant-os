# Agentic AI Core & Local Inference Architecture

## Overview
Revenant OS is engineered from the ground up to be **Local-First**. It provides a fully functioning, high-performance offline AI agent stack that runs on the Toughbook CF-52's CPU without needing an internet connection, accounts, or subscriptions.

---

## Core Inference Stack

### 1. Embedded `llama-server` (`:8080`)
- **System Service**: Managed by `systemd` (`llama-server.service`).
- **Binary Location**: `/opt/llama.cpp/llama-server`
- **Default Port**: `http://127.0.0.1:8080/v1` (OpenAI-compatible)
- **Active Model**: `Qwen2.5-Coder-1.5B-Instruct` (Q4_K_M GGUF) in `/opt/models/`
- **Hardware Optimization**: Configured for 2 CPU threads with 2048 context window size, consuming ~1.8 GB RAM.
- **Service Commands**:
  ```bash
  sudo systemctl status llama-server
  sudo systemctl restart llama-server
  ```

### 2. Universal Terminal AI (`ai`)
Revenant OS provides an instant command-line AI assistant:
```bash
ai "How do I check battery capacity on this Toughbook?"
ai "Write a bash one-liner to parse failed logins in /var/log/auth.log"
```
- Sends your question to `http://127.0.0.1:8080/v1/chat/completions`.
- Formats and displays the response in the terminal.
- Automatically reads the response aloud using the offline Piper neural TTS engine.

### 3. OpenViking Automated Context Database
- **System Service**: `openviking.service`
- Runs in the background, continuously storing agent interactions, commands, and environment discoveries.
- Provides persistent memory across agent sessions without needing huge raw context windows.
- Access via CLI:
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
Because of this standard setup:
- **OpenInterpreter** runs immediately in terminal mode:
  ```bash
  interpreter
  ```
- **Hermes Agent** executes role-based autonomous multi-step tasks against the local Qwen model.

### 5. Offline Neural Speech Synthesis (Piper TTS)
- Pre-packaged neural voice model: `en_US-lessac-medium.onnx` located in `/opt/piper/models/`.
- Fast, natural offline synthesis computed on CPU and streamed to ALSA audio.
