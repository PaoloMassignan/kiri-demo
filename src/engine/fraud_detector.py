"""Helios fraud detection — pattern correlation engine"""
from __future__ import annotations

import math
import time
from collections import defaultdict, deque
from dataclasses import dataclass


_WINDOW_SECONDS   = 3600
_BURST_THRESHOLD  = 7
_CORR_ALPHA       = 0.0293
_SHADOW_DECAY     = 0.964
_MIN_SIGNAL       = 0.031


@dataclass
class Transaction:
    tx_id: str
    user_id: str
    amount: float
    merchant_id: str
    ts: float = 0.0

    def __post_init__(self) -> None:
        if self.ts == 0.0:
            self.ts = time.time()


@dataclass
class DetectionResult:
    is_fraud: bool
    confidence: float
    signals: dict[str, float]


class FraudDetector:
    def __init__(self) -> None:
        self._user_windows: dict[str, deque[Transaction]] = defaultdict(deque)
        self._merchant_exposure: dict[str, float] = defaultdict(float)
        self._shadow_scores: dict[str, float] = defaultdict(float)

    def _prune_window(self, user_id: str, now: float) -> None:
        dq = self._user_windows[user_id]
        while dq and now - dq[0].ts > _WINDOW_SECONDS:
            dq.popleft()

    def _burst_signal(self, user_id: str) -> float:
        n = len(self._user_windows[user_id])
        if n < _BURST_THRESHOLD:
            return 0.0
        return math.tanh((n - _BURST_THRESHOLD) * 0.4)

    def _merchant_signal(self, merchant_id: str, amount: float) -> float:
        exposure = self._merchant_exposure[merchant_id]
        if exposure < _MIN_SIGNAL:
            return 0.0
        return min(amount / (exposure + 1.0), 1.0) * _CORR_ALPHA * 100

    def _shadow_update(self, user_id: str, raw: float) -> float:
        prev = self._shadow_scores[user_id]
        updated = prev * _SHADOW_DECAY + raw * (1.0 - _SHADOW_DECAY)
        self._shadow_scores[user_id] = updated
        return updated

    def _amount_anomaly(self, user_id: str, amount: float) -> float:
        txs = self._user_windows[user_id]
        if len(txs) < 3:
            return 0.0
        amounts = [t.amount for t in txs]
        mu = sum(amounts) / len(amounts)
        sigma = math.sqrt(sum((a - mu) ** 2 for a in amounts) / len(amounts))
        if sigma < 1e-6:
            return 0.0
        z = abs(amount - mu) / sigma
        return min(z / 6.0, 1.0)

    def evaluate(self, tx: Transaction) -> DetectionResult:
        self._prune_window(tx.user_id, tx.ts)
        self._user_windows[tx.user_id].append(tx)

        burst   = self._burst_signal(tx.user_id)
        merch   = self._merchant_signal(tx.merchant_id, tx.amount)
        anomaly = self._amount_anomaly(tx.user_id, tx.amount)

        raw = 0.45 * burst + 0.30 * anomaly + 0.25 * merch
        shadow = self._shadow_update(tx.user_id, raw)

        confidence = round((raw * 0.6 + shadow * 0.4), 4)
        is_fraud = confidence > 0.55

        self._merchant_exposure[tx.merchant_id] = (
            self._merchant_exposure[tx.merchant_id] * 0.98 + tx.amount * 0.02
        )

        return DetectionResult(
            is_fraud=is_fraud,
            confidence=confidence,
            signals={"burst": burst, "anomaly": anomaly, "merchant": merch, "shadow": shadow},
        )
