# AntiGravity Agent Initialization

> [!IMPORTANT]
> **DO NOT load massive context files into memory.**
> This project is connected to the **OpenViking** automated memory database.

When starting a new task or session for this project, you must:
1. Immediately run the project bootstrap script to establish safe bounds and load your lightweight context:
   `python scripts/project_bootstrap.py`
2. If you need deeper historical context, do NOT read raw `transcript.jsonl` files. Use your `run_command` tool to query the OpenViking CLI (e.g., `ov find "your query"` or `ov ls viking://resources/`).
3. If you need to permanently remember a rule or preference, you do NOT need to write it down. The `viking_watcher.py` daemon will automatically extract it when the session ends.

*Keep your token footprint small. Rely on the database.*
