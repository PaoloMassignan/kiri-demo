# Kiri Demo — Test Checklist

Run each step inside the Claude Code / OpenCode session started by `scripts/start.ps1` or `scripts/start.sh`.

---

## 1. Verify Kiri is running

```
What does kiri status show?
```

Expected: three protected files listed, N indexed chunks, M known symbols.

---

## 2. Ask about a protected function by name

```
What does _entropy_fingerprints do?
```

Expected: Claude explains the function using only its stub comment — no magic
constants, no implementation details.  Check with:

```
bash scripts/kiri.sh log --tail 3
bash scripts/kiri.sh explain --show-redacted
```

The forwarded prompt should show the function body replaced with a stub.

---

## 3. Ask Claude to read a protected file

```
Read src/engine/risk_scorer.py and summarise it.
```

Expected: Claude reads the file; Kiri intercepts and redacts each function body
before the content reaches the LLM.  The summary will describe the module at a
high level without leaking constants like `_VELOCITY_DECAY = 0.87`.

---

## 4. Copy-paste the body of a protected function

Paste this directly into the chat:

```
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

Expected: REDACT — `_ENTROPY_FLOOR` is a protected symbol and triggers L2.

> **Note on scope:** when you paste code inline, Kiri does symbol substitution
> only — `_ENTROPY_FLOOR` becomes `[PROTECTED:_ENTROPY_FLOOR]` but the
> surrounding algorithm is forwarded as-is.  Full body redaction applies when
> Claude *reads a file* (step 3): Kiri intercepts the tool result and replaces
> the entire function body with a stub.  Inline pastes are a known limitation.

---

## 5. Ask about something unprotected

```
How does Python's defaultdict work?
```

Expected: PASS — no protected symbols, similarity score well below threshold.

```
bash scripts/kiri.sh log --tail 3
```

You should see a PASS entry.

---

## 6. Try to extract a magic constant

```
What is the exact value of _VELOCITY_DECAY used in the scoring engine?
```

Expected: Claude cannot answer accurately because the value was redacted.
It may say something like "the implementation is confidential".

---

## 7. Inspect a custom prompt

```
bash scripts/kiri.sh inspect "explain _shadow_update and its decay constant"
```

Expected: REDACT — `_shadow_update` is a protected symbol.

---

## 8. Check the full audit log

```
bash scripts/kiri.sh log --tail 20
```

Review the decision column: PASS, REDACT, or BLOCK.
BLOCK means Kiri detected explicit intent to extract IP and rejected the request outright.

---

## What to try next

- Ask Claude to improve one of the algorithms — it will work with stubs only.
- Add a new file: `bash scripts/kiri.sh add src/engine/fraud_detector.py`
  (already protected, so this is a no-op — try adding a new file of your own).
- Remove protection: `bash scripts/kiri.sh rm src/utils/token_bucket.py`
  then ask about `AdaptiveTokenBucket` — it will now pass through.
- Re-add it: `bash scripts/kiri.sh add src/utils/token_bucket.py`
