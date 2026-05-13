# kiri-demo — Claude Code context

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

Run kiri commands with:

```bash
bash scripts/kiri.sh <subcommand>
```

| Intent | Command |
|--------|---------|
| Show what is protected | `bash scripts/kiri.sh status` |
| Show last 10 decisions | `bash scripts/kiri.sh log --tail 10` |
| Explain last decision | `bash scripts/kiri.sh explain` |
| Show redacted prompt | `bash scripts/kiri.sh explain --show-redacted` |
| Protect a file | `bash scripts/kiri.sh add <path>` |
| Remove protection | `bash scripts/kiri.sh rm <path>` |
| Inspect a prompt | `bash scripts/kiri.sh inspect "<text>"` |
