# Kiri Demo — Test Checklist

Run each step inside the LLM session started by `scripts/start.ps1` or `scripts/start.sh`.
For terminal commands use whichever matches your OS:

```bash
bash scripts/kiri.sh <cmd>      # Linux / Mac
```
```powershell
.\scripts\kiri.ps1 <cmd>        # Windows
```

---

## 1. Verify Kiri is running

Run directly in your terminal (outside the LLM session):

```bash
bash scripts/kiri.sh status
```
```powershell
.\scripts\kiri.ps1 status
```

Expected: three protected files listed, N indexed chunks, M known symbols.

---

## 2. Ask about a protected function by name

Send this message to the LLM:

```
What does _entropy_fingerprints do?
```

Expected: the LLM explains the function using only its stub comment — no magic
constants, no implementation details. Kiri redacted the body before it reached
the model. Verify with:

```bash
bash scripts/kiri.sh log --tail 3
bash scripts/kiri.sh explain --show-redacted
```
```powershell
.\scripts\kiri.ps1 log --tail 3
.\scripts\kiri.ps1 explain --show-redacted
```

The forwarded prompt should show the function body replaced with a stub.

---

## 3. Copy-paste the body of a protected function

Paste the **entire block below** (including the triple backticks) into the chat:

````
What does this code do?

```python
    if not fps:
        return 0.0
    counts: dict[str, int] = {}
    for fp in fps:
        h = hashlib.sha1(fp.encode()).hexdigest()[:6]
        counts[h] = counts.get(h, 0) + 1
    total = len(fps)
    entropy = -sum((c / total) * math.log2(c / total) for c in counts.values())
    return min(entropy / max(math.log2(total + 1), _ENTROPY_FLOOR), 1.0)
```
````

Expected: REDACT — `_ENTROPY_FLOOR` triggers L2 and Kiri replaces the **entire
fenced code block** with a stub. The algorithm logic (Shannon entropy, SHA-1
hashing) does not reach the LLM — only a `# [redacted]` stub does.

---

## 4. Ask about something unprotected

```
How does Python's defaultdict work?
```

Expected: PASS — no protected symbols, similarity score well below threshold.

```bash
bash scripts/kiri.sh log --tail 3
```
```powershell
.\scripts\kiri.ps1 log --tail 3
```

You should see a PASS entry.

---

## 5. Try to extract a magic constant

```
What is the exact value of _VELOCITY_DECAY used in the scoring engine?
```

Expected: the LLM cannot answer accurately because the value was redacted.
It may say the implementation is not available or the constant is unknown.

---

## 6. Inspect a custom prompt (terminal)

```bash
bash scripts/kiri.sh inspect "explain _shadow_update and its decay constant"
```
```powershell
.\scripts\kiri.ps1 inspect "explain _shadow_update and its decay constant"
```

Expected: REDACT — `_shadow_update` is a protected symbol.

---

## 7. Check the full audit log

```bash
bash scripts/kiri.sh log --tail 20
```
```powershell
.\scripts\kiri.ps1 log --tail 20
```

Review the decision column: PASS, REDACT, or BLOCK.
BLOCK means Kiri detected explicit intent to extract IP and rejected the request outright.

---

## What to try next

- Ask the LLM to improve one of the algorithms — it will work with stubs only.
- Remove protection and re-add it:

```bash
bash scripts/kiri.sh rm src/utils/token_bucket.py
# ask about AdaptiveTokenBucket — now passes through
bash scripts/kiri.sh add src/utils/token_bucket.py
# protection restored
```
```powershell
.\scripts\kiri.ps1 rm src/utils/token_bucket.py
# ask about AdaptiveTokenBucket — now passes through
.\scripts\kiri.ps1 add src/utils/token_bucket.py
# protection restored
```

---

> **Local mode note** (Option A — free local LLM): response quality is lower
> than Claude, but Kiri's redaction works identically. The demo steps above are
> designed to work with any model.
