# kiri-demo — OpenCode context

This repo contains **fictional proprietary algorithms** used to demonstrate Kiri's
redaction pipeline. The code is invented and does not belong to any real system.

Kiri is running as a local proxy on `http://localhost:8765`.  Every message you
send passes through it before reaching Anthropic.

## Protected files

The following files are protected — their implementations are confidential:

- `src/engine/risk_scorer.py`
- `src/engine/fraud_detector.py`
- `src/utils/token_bucket.py`

When you read or discuss these files, Kiri will replace function bodies with
stub comments before forwarding to the LLM.

## Kiri CLI

**Linux / Mac (bash):**
```bash
bash scripts/kiri.sh <subcommand>
```

**Windows (PowerShell):**
```powershell
.\scripts\kiri.ps1 <subcommand>
```

| Intent | Command |
|--------|---------|
| Show what is protected | `status` |
| Show last 10 decisions | `log --tail 10` |
| Explain last decision | `explain` |
| Show redacted prompt | `explain --show-redacted` |
| Protect a file | `add <path>` |
| Remove protection | `rm <path>` |
| Inspect a prompt | `inspect "<text>"` |
